# GitHub tools for Pepe, as a drop-in plugin.
#
# Five tools: search issues and pull requests, read one (with its latest comments, and the state
# of a pull request), read a file or list a folder of a repository, create an issue, comment.
# Each is an ordinary Pepe tool, so an agent holds exactly the ones it is given, and every write
# still passes the permission gate.
#
# Auth is an access token (a fine-grained personal access token is the safe choice: it can be
# limited to chosen repositories and to the permissions you list). Settings come from the
# plugin's Configure dialog, falling back to environment variables:
#
#   * token         / GITHUB_TOKEN          the access token
#   * default_repo  / GITHUB_REPO           owner/name used when a call names no repository
#   * allowed_repos / GITHUB_ALLOWED_REPOS  comma separated owner/name, owner/* or * the agent may WRITE to; empty = read only
#   * api_url       / GITHUB_API_URL        only for GitHub Enterprise Server, like https://git.example.com/api/v3

defmodule Pepe.Plugins.GitHub.Client do
  @moduledoc """
  Settings, the HTTP calls, and the one-line summaries the tools share.
  """

  @repo_re ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/
  @ref_re ~r/\A[A-Za-z0-9._\/-]+\z/

  # ---- settings ------------------------------------------------------------------------

  @doc "The connection settings, or `{:error, message}` naming what is missing."
  def settings do
    case setting("token", "GITHUB_TOKEN") do
      nil ->
        {:error, "GitHub is not configured. Set an access token under Plugins -> Configure (or the GITHUB_TOKEN env var)."}

      token ->
        base = (setting("api_url", "GITHUB_API_URL") || "https://api.github.com") |> String.trim() |> String.trim_trailing("/")
        {:ok, %{base: base, token: token}}
    end
  end

  @doc "The `owner/name` (or `owner/*`, or `*`) the agent may write to, or `nil` when none were listed."
  def allowed_repos do
    case setting("allowed_repos", "GITHUB_ALLOWED_REPOS") do
      nil -> nil
      list -> list |> String.split([",", " "], trim: true) |> Enum.map(&String.downcase/1)
    end
  end

  defp setting(key, env_key), do: Pepe.Plugins.config("github", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # ---- repository, number, path ----------------------------------------------------------

  @doc "The repository a call is about: the one named, else the default. Validated as `owner/name`."
  def repo(value) do
    value = value |> blank() || setting("default_repo", "GITHUB_REPO")

    cond do
      is_nil(value) -> {:error, "No repository given and no default repository is configured."}
      Regex.match?(@repo_re, String.trim(value)) -> {:ok, String.trim(value)}
      true -> {:error, "#{inspect(value)} is not a repository (like owner/name)."}
    end
  end

  @doc "An issue or pull request number, from an integer or a numeric string."
  def number(value) when is_integer(value) and value > 0, do: {:ok, value}

  def number(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(String.trim(value), "#")) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, "#{inspect(value)} is not an issue or pull request number."}
    end
  end

  def number(value), do: {:error, "#{inspect(value)} is not an issue or pull request number."}

  @doc "A path inside a repository, safe to put in a URL: no `..`, each part encoded."
  def path(value) do
    parts = value |> to_string() |> String.split("/", trim: true)

    if ".." in parts or "." in parts do
      {:error, "A path may not contain . or .. parts."}
    else
      {:ok, parts |> Enum.map(&URI.encode(&1, fn char -> URI.char_unreserved?(char) end)) |> Enum.join("/")}
    end
  end

  @doc "A branch, tag or commit, or nil."
  def ref(nil), do: {:ok, nil}

  def ref(value) do
    case blank(value) do
      nil -> {:ok, nil}
      ref -> if Regex.match?(@ref_re, ref), do: {:ok, ref}, else: {:error, "#{inspect(value)} is not a branch, tag or commit."}
    end
  end

  @doc """
  May the agent write to this repository? Writing is off until the operator lists the repositories
  it may change (`*` for any), so a plugin that was just installed can read but never change
  anything by accident.
  """
  def writable?(repo) do
    case allowed_repos() do
      nil ->
        {:error, "Writing to GitHub is off. List the repositories this agent may change (or *) under Plugins -> Configure."}

      list ->
        [owner, _name] = repo |> String.downcase() |> String.split("/")

        if "*" in list or String.downcase(repo) in list or "#{owner}/*" in list,
          do: :ok,
          else: {:error, "This agent may not change #{repo}. Allowed: #{Enum.join(list, ", ")}."}
    end
  end

  def blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  def blank(_value), do: nil

  # ---- http ----------------------------------------------------------------------------

  def get(settings, path, params \\ []), do: request(settings, :get, path, params: params)
  def post(settings, path, body), do: request(settings, :post, path, json: body)

  defp request(settings, method, path, opts) do
    opts =
      Keyword.merge(
        [
          method: method,
          url: settings.base <> path,
          auth: {:bearer, settings.token},
          headers: [
            {"accept", "application/vnd.github+json"},
            {"x-github-api-version", "2022-11-28"},
            {"user-agent", "pepe-github-plugin"}
          ],
          receive_timeout: 20_000,
          # A rate limit is told to the agent at once (the message says how long to wait). Left to
          # the HTTP client, it would sleep for the whole Retry-After, three times, inside the turn.
          retry: false
        ],
        opts
      )

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body} = response} -> {:error, explain(status, body, response)}
      {:error, reason} -> {:error, "Could not reach GitHub: #{inspect(reason)}"}
    end
  end

  defp explain(401, _body, _response), do: "GitHub did not accept the access token. Check that it is current and has not expired."

  defp explain(403, body, response) do
    if Req.Response.get_header(response, "x-ratelimit-remaining") == ["0"],
      do: "GitHub is rate limiting this token. Try again later.",
      else: "GitHub says this token is not allowed to do that#{detail(body)}"
  end

  defp explain(404, _body, _response), do: "GitHub could not find it (or this token cannot see it; a private repository looks the same)."

  defp explain(422, body, _response), do: "GitHub refused it#{detail(body)}"
  defp explain(status, body, _response), do: "GitHub answered with an error (#{status})#{detail(body)}"

  defp detail(%{"message" => message} = body) do
    problems = for %{"message" => m} <- List.wrap(body["errors"]), do: m
    ": " <> Enum.join([message | problems], "; ")
  end

  defp detail(_body), do: "."

  # ---- what comes back -------------------------------------------------------------------

  @doc """
  Text that came out of GitHub is written by whoever opened the issue or pushed the file, so it
  reaches the model framed as quoted material, never as instructions.
  """
  def external(text) do
    Pepe.Security.ExternalContent.mark_untrusted("github", Pepe.Security.ExternalContent.sanitize(text))
  end

  @doc "The `owner/name` an item belongs to, from its repository URL."
  def repo_of(%{"repository_url" => url}) when is_binary(url), do: url |> String.split("/") |> Enum.take(-2) |> Enum.join("/")
  def repo_of(_item), do: nil

  @doc "One line for an issue or pull request."
  def line(item, repo \\ nil) do
    kind = if item["pull_request"], do: "pull request", else: "issue"
    labels = for %{"name" => name} <- List.wrap(item["labels"]), do: name
    label_text = if labels == [], do: "", else: ", labels: " <> Enum.join(labels, " ")

    "#{repo || repo_of(item)}##{item["number"]}: #{item["title"]} (#{item["state"]}, #{kind}, by #{get_in(item, ["user", "login"])}#{label_text})"
  end

  @doc "Cut a text to a length, saying so when it was cut."
  def clip(text, max) do
    text = to_string(text)
    if String.length(text) > max, do: String.slice(text, 0, max) <> "\n[... cut, #{String.length(text) - max} more characters]", else: text
  end
end

defmodule Pepe.Plugins.GitHubSearch do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.GitHub.Client

  @impl true
  def name, do: "github_search"

  @impl true
  def spec do
    function(
      "github_search",
      "Search GitHub issues and pull requests. Uses GitHub's search syntax, for example: " <>
        "repo:owner/name is:open is:pr label:bug login error.",
      %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "The search, with GitHub qualifiers (repo:, is:open, is:pr, author:, label:)."},
          "max" => %{"type" => "integer", "description" => "How many to return (1 to 30, default 10)."}
        },
        "required" => ["query"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  # What a search returns was written by whoever opened the issues.
  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"query" => query} = args, _ctx) when is_binary(query) and query != "" do
    max = if is_integer(args["max"]), do: args["max"] |> min(30) |> max(1), else: 10

    with {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/search/issues", q: query, per_page: max) do
      case body["items"] do
        [_ | _] = items ->
          lines = Enum.map_join(items, "\n", &Client.line/1)
          {:ok, Client.external("#{body["total_count"]} found, showing #{length(items)}:\n" <> lines)}

        _ ->
          {:ok, "Nothing matches that search."}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "github_search needs a `query`."}
end

defmodule Pepe.Plugins.GitHubGetIssue do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.GitHub.Client

  @impl true
  def name, do: "github_get_issue"

  @impl true
  def spec do
    function(
      "github_get_issue",
      "Read one GitHub issue or pull request: who opened it, state, labels, its text and the latest comments. " <>
        "For a pull request it also gives the branches and whether it was merged.",
      %{
        "type" => "object",
        "properties" => %{
          "repo" => %{"type" => "string", "description" => "owner/name (optional if a default repository is set)."},
          "number" => %{"type" => "integer", "description" => "The issue or pull request number."},
          "comments" => %{"type" => "integer", "description" => "How many of the latest comments to include (0 to 20, default 5)."}
        },
        "required" => ["number"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"number" => number} = args, _ctx) do
    comments = if is_integer(args["comments"]), do: args["comments"] |> min(20) |> max(0), else: 5

    with {:ok, repo} <- Client.repo(args["repo"]),
         {:ok, number} <- Client.number(number),
         {:ok, settings} <- Client.settings(),
         {:ok, issue} <- Client.get(settings, "/repos/#{repo}/issues/#{number}"),
         {:ok, pull} <- pull_request(settings, repo, number, issue),
         {:ok, thread} <- latest_comments(settings, repo, number, issue, comments) do
      {:ok, issue |> render(repo, pull, thread) |> Client.external()}
    end
  end

  def run(_args, _ctx), do: {:error, "github_get_issue needs a `number`."}

  defp pull_request(settings, repo, number, %{"pull_request" => _}), do: Client.get(settings, "/repos/#{repo}/pulls/#{number}")
  defp pull_request(_settings, _repo, _number, _issue), do: {:ok, nil}

  defp latest_comments(_settings, _repo, _number, _issue, 0), do: {:ok, []}
  defp latest_comments(_settings, _repo, _number, %{"comments" => 0}, _max), do: {:ok, []}

  # Comments come oldest first; the last page holds the newest.
  defp latest_comments(settings, repo, number, issue, max) do
    page = ceil((issue["comments"] || 1) / 100)

    with {:ok, list} <- Client.get(settings, "/repos/#{repo}/issues/#{number}/comments", per_page: 100, page: page) do
      {:ok, list |> List.wrap() |> Enum.take(-max)}
    end
  end

  defp render(issue, repo, pull, comments) do
    header = [
      Client.line(issue, repo),
      "Link: #{issue["html_url"]}",
      "Opened: #{issue["created_at"]}   Updated: #{issue["updated_at"]}",
      "Assignees: #{issue["assignees"] |> List.wrap() |> Enum.map_join(", ", & &1["login"]) |> empty("none")}"
    ]

    body = if is_nil(Client.blank(issue["body"])), do: ["", "(no text)"], else: ["", Client.clip(issue["body"], 6000)]

    thread =
      case comments do
        [] ->
          []

        list ->
          [
            "",
            "Latest comments:" | Enum.map(list, &"[#{&1["created_at"]}] #{get_in(&1, ["user", "login"])}: #{Client.clip(&1["body"], 1500)}")
          ]
      end

    Enum.join(header ++ pull_lines(pull) ++ body ++ thread, "\n")
  end

  defp pull_lines(nil), do: []

  defp pull_lines(pull) do
    state =
      cond do
        pull["merged"] -> "merged"
        pull["draft"] -> "draft"
        true -> pull["state"]
      end

    [
      "Pull request: #{state}, #{get_in(pull, ["head", "ref"])} into #{get_in(pull, ["base", "ref"])}, " <>
        "#{pull["changed_files"]} files changed (+#{pull["additions"]} -#{pull["deletions"]})"
    ]
  end

  defp empty("", fallback), do: fallback
  defp empty(text, _fallback), do: text
end

defmodule Pepe.Plugins.GitHubGetFile do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.GitHub.Client

  # What is worth putting in front of a model, and the biggest file worth downloading to find out.
  @max_chars 20_000
  @max_bytes 500_000

  @impl true
  def name, do: "github_get_file"

  @impl true
  def spec do
    function(
      "github_get_file",
      "Read a text file from a GitHub repository, or list a folder. Leave `path` empty for the top of the repository.",
      %{
        "type" => "object",
        "properties" => %{
          "repo" => %{"type" => "string", "description" => "owner/name (optional if a default repository is set)."},
          "path" => %{"type" => "string", "description" => "A file or folder path, like lib/app.ex. Empty for the top."},
          "ref" => %{"type" => "string", "description" => "A branch, tag or commit (default: the repository's main branch)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true

  # A repository's files are written by whoever can push to it.
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    with {:ok, repo} <- Client.repo(args["repo"]),
         {:ok, path} <- Client.path(args["path"] || ""),
         {:ok, ref} <- Client.ref(args["ref"]),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/repos/#{repo}/contents/#{path}", if(ref, do: [ref: ref], else: [])) do
      body |> render(repo, args["path"]) |> wrap()
    end
  end

  defp wrap({:ok, text}), do: {:ok, Client.external(text)}
  defp wrap(error), do: error

  defp render(items, repo, path) when is_list(items) do
    lines =
      items
      |> Enum.sort_by(&{&1["type"] != "dir", &1["name"]})
      |> Enum.map_join("\n", fn item ->
        if item["type"] == "dir", do: item["name"] <> "/", else: "#{item["name"]} (#{item["size"]} bytes)"
      end)

    {:ok, "#{repo}/#{path || ""} has:\n#{lines}"}
  end

  defp render(%{"type" => "file", "size" => size}, repo, path) when size > @max_bytes,
    do: {:error, "#{repo}/#{path} is #{size} bytes, too large to read here."}

  defp render(%{"type" => "file", "content" => content, "encoding" => "base64"}, repo, path) do
    bytes = Base.decode64!(content, ignore: :whitespace)

    if String.valid?(bytes),
      do: {:ok, "#{repo}/#{path}:\n" <> Client.clip(bytes, @max_chars)},
      else: {:ok, "#{repo}/#{path} is not a text file (#{byte_size(bytes)} bytes)."}
  end

  defp render(%{"type" => type}, repo, path), do: {:error, "#{repo}/#{path} is a #{type}, which cannot be read here."}
  defp render(_other, repo, path), do: {:error, "GitHub gave back something unexpected for #{repo}/#{path}."}
end

defmodule Pepe.Plugins.GitHubCreateIssue do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.GitHub.Client

  @impl true
  def name, do: "github_create_issue"

  @impl true
  def spec do
    function("github_create_issue", "Open an issue in a GitHub repository. Gives back its number and link.", %{
      "type" => "object",
      "properties" => %{
        "repo" => %{"type" => "string", "description" => "owner/name (optional if a default repository is set)."},
        "title" => %{"type" => "string", "description" => "The title."},
        "body" => %{"type" => "string", "description" => "The text, in Markdown."},
        "labels" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Labels to add (they must exist)."},
        "assignees" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "GitHub usernames to assign."}
      },
      "required" => ["title"]
    })
  end

  @impl true
  def run(%{"title" => title} = args, _ctx) when is_binary(title) and title != "" do
    with {:ok, repo} <- Client.repo(args["repo"]),
         :ok <- Client.writable?(repo),
         {:ok, settings} <- Client.settings(),
         {:ok, issue} <- Client.post(settings, "/repos/#{repo}/issues", payload(title, args)) do
      {:ok, "Opened #{repo}##{issue["number"]}: #{issue["html_url"]}"}
    end
  end

  def run(_args, _ctx), do: {:error, "github_create_issue needs a `title`."}

  defp payload(title, args) do
    %{"title" => title}
    |> put("body", Client.blank(args["body"]))
    |> put("labels", strings(args["labels"]))
    |> put("assignees", strings(args["assignees"]))
  end

  defp strings(list) when is_list(list), do: list |> Enum.filter(&is_binary/1) |> then(&if(&1 == [], do: nil, else: &1))
  defp strings(_other), do: nil

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end

defmodule Pepe.Plugins.GitHubComment do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.GitHub.Client

  @impl true
  def name, do: "github_comment"

  @impl true
  def spec do
    function("github_comment", "Comment on a GitHub issue or pull request.", %{
      "type" => "object",
      "properties" => %{
        "repo" => %{"type" => "string", "description" => "owner/name (optional if a default repository is set)."},
        "number" => %{"type" => "integer", "description" => "The issue or pull request number."},
        "comment" => %{"type" => "string", "description" => "The comment, in Markdown."}
      },
      "required" => ["number", "comment"]
    })
  end

  @impl true
  def run(%{"number" => number, "comment" => comment} = args, _ctx) when is_binary(comment) and comment != "" do
    with {:ok, repo} <- Client.repo(args["repo"]),
         {:ok, number} <- Client.number(number),
         :ok <- Client.writable?(repo),
         {:ok, settings} <- Client.settings(),
         {:ok, posted} <- Client.post(settings, "/repos/#{repo}/issues/#{number}/comments", %{"body" => comment}) do
      {:ok, "Commented on #{repo}##{number}: #{posted["html_url"]}"}
    end
  end

  def run(_args, _ctx), do: {:error, "github_comment needs a `number` and a `comment`."}
end
