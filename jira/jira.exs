# Jira Cloud tools for Pepe, as a drop-in plugin.
#
# Five tools: search (JQL), read an issue with its latest comments, create an issue, comment, and
# move an issue through its workflow. Each is an ordinary Pepe tool, so an agent holds exactly
# the ones it is given, and every write still passes the permission gate.
#
# Auth is a Jira Cloud API token (Basic auth, your e-mail plus the token). Settings come from the
# plugin's Configure dialog, falling back to environment variables, so it works whichever way you
# prefer to keep the secret:
#
#   * site             / JIRA_SITE             e.g. yourcompany.atlassian.net
#   * email            / JIRA_EMAIL
#   * api_token        / JIRA_API_TOKEN
#   * default_project  / JIRA_PROJECT          project key used when a create names none
#   * allowed_projects / JIRA_ALLOWED_PROJECTS comma separated keys the agent may WRITE to (* for any); empty = read only
#
# Jira Cloud only (REST API v3). Jira Server / Data Center authenticates differently.

defmodule Pepe.Plugins.Jira.Client do
  @moduledoc """
  Settings, the HTTP calls, and the two conversions Jira needs: its rich-text format (ADF) to
  plain text for the model to read, and plain text back to ADF for what the model writes.
  """

  @key_re ~r/\A[A-Z][A-Z0-9_]*-\d+\z/

  # ---- settings ------------------------------------------------------------------------

  @doc "The connection settings, or `{:error, message}` naming what is missing."
  def settings do
    site = setting("site", "JIRA_SITE")
    email = setting("email", "JIRA_EMAIL")
    token = setting("api_token", "JIRA_API_TOKEN")

    if site && email && token do
      {:ok, %{base: base_url(site), email: email, token: token}}
    else
      {:error,
       "Jira is not configured. Set the site (like yourcompany.atlassian.net), your e-mail and an " <>
         "API token under Plugins -> Configure (or the JIRA_SITE, JIRA_EMAIL and JIRA_API_TOKEN env vars)."}
    end
  end

  @doc "The project key a create falls back to, or nil."
  def default_project, do: setting("default_project", "JIRA_PROJECT")

  @doc "The project keys the agent may write to (`*` for any), or `nil` when none were listed."
  def allowed_projects do
    case setting("allowed_projects", "JIRA_ALLOWED_PROJECTS") do
      nil -> nil
      list -> list |> String.split([",", " "], trim: true) |> Enum.map(&String.upcase/1)
    end
  end

  # `yourcompany.atlassian.net` or a full URL (kept as given, which is also what lets a test
  # point at a local server).
  defp base_url(site) do
    site = site |> String.trim() |> String.trim_trailing("/")
    if String.starts_with?(site, ["http://", "https://"]), do: site, else: "https://" <> site
  end

  defp setting(key, env_key), do: Pepe.Plugins.config("jira", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # ---- keys ----------------------------------------------------------------------------

  @doc "An issue key such as `CNSUP-123`, validated so it can never smuggle a path into the URL."
  def issue_key(value) do
    key = value |> to_string() |> String.trim() |> String.upcase()
    if Regex.match?(@key_re, key), do: {:ok, key}, else: {:error, "#{inspect(value)} is not a Jira issue key (like CNSUP-123)."}
  end

  @doc """
  May the agent write to the project this key (or project key) belongs to? Writing is off until
  the operator lists the projects it may change (`*` for any), so a plugin that was just installed
  can read but never change anything by accident.
  """
  def writable?(key_or_project) do
    project = key_or_project |> to_string() |> String.upcase() |> String.split("-") |> hd()

    case allowed_projects() do
      nil ->
        {:error, "Writing to Jira is off. List the projects this agent may change (or *) under Plugins -> Configure."}

      list ->
        if "*" in list or project in list,
          do: :ok,
          else: {:error, "This agent may not change project #{project}. Allowed: #{Enum.join(list, ", ")}."}
    end
  end

  # ---- http ----------------------------------------------------------------------------

  def get(settings, path, params \\ []), do: request(settings, :get, path, params: params)
  def post(settings, path, body), do: request(settings, :post, path, json: body)

  defp request(settings, method, path, opts) do
    opts =
      Keyword.merge(
        [
          method: method,
          url: settings.base <> "/rest/api/3" <> path,
          auth: {:basic, "#{settings.email}:#{settings.token}"},
          headers: [{"accept", "application/json"}],
          receive_timeout: 20_000
        ],
        opts
      )

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, explain(status, body)}
      {:error, reason} -> {:error, "Could not reach Jira: #{inspect(reason)}"}
    end
  end

  defp explain(401, _body), do: "Jira did not accept the e-mail and API token. Check the e-mail and that the token is current."
  defp explain(403, _body), do: "Jira says this account is not allowed to do that."
  defp explain(404, _body), do: "Jira could not find it (or this account cannot see it)."
  defp explain(429, _body), do: "Jira is rate limiting this account. Try again in a moment."

  defp explain(status, %{"errorMessages" => messages, "errors" => errors}) do
    detail = (List.wrap(messages) ++ for({field, message} <- errors || %{}, do: "#{field}: #{message}")) |> Enum.join("; ")
    "Jira refused it (#{status}): #{if detail == "", do: "no detail given", else: detail}"
  end

  defp explain(status, _body), do: "Jira answered with an error (#{status})."

  # ---- text <-> ADF ----------------------------------------------------------------------

  @doc "Plain text as an Atlassian Document: blank lines split paragraphs, single newlines are line breaks."
  def to_adf(text) do
    paragraphs =
      text
      |> to_string()
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map(fn paragraph ->
        content =
          paragraph
          |> String.split("\n")
          |> Enum.map(&%{"type" => "text", "text" => &1})
          |> Enum.intersperse(%{"type" => "hardBreak"})

        %{"type" => "paragraph", "content" => content}
      end)

    %{"type" => "doc", "version" => 1, "content" => paragraphs}
  end

  @doc "An Atlassian Document (or a plain string, or nil) as readable text."
  def from_adf(nil), do: ""
  def from_adf(text) when is_binary(text), do: text
  def from_adf(%{} = node), do: node |> render() |> String.trim()
  def from_adf(_other), do: ""

  defp render(%{"type" => "text", "text" => text}), do: text
  defp render(%{"type" => "hardBreak"}), do: "\n"
  defp render(%{"type" => "mention", "attrs" => %{"text" => text}}), do: text
  defp render(%{"type" => "inlineCard", "attrs" => %{"url" => url}}), do: url
  defp render(%{"type" => "emoji", "attrs" => attrs}), do: attrs["text"] || attrs["shortName"] || ""
  defp render(%{"type" => type}) when type in ["media", "mediaSingle", "mediaGroup", "mediaInline"], do: "[attachment]"

  defp render(%{"type" => type, "content" => items}) when type in ["bulletList", "orderedList"],
    do: Enum.map_join(items, "", &("- " <> String.trim(render(&1)) <> "\n"))

  defp render(%{"type" => type, "content" => content})
       when type in ["paragraph", "heading", "listItem", "codeBlock", "blockquote", "panel", "tableRow"],
       do: Enum.map_join(content, "", &render/1) <> "\n"

  defp render(%{"content" => content}) when is_list(content), do: Enum.map_join(content, "", &render/1)
  defp render(_node), do: ""

  # ---- what comes back -------------------------------------------------------------------

  @doc """
  Text that came out of Jira is written by whoever filed the issue, so it reaches the model framed
  as quoted material, never as instructions.
  """
  def external(text) do
    Pepe.Security.ExternalContent.mark_untrusted("jira", Pepe.Security.ExternalContent.sanitize(text))
  end

  @doc "A link to an issue in the browser."
  def browse_url(settings, key), do: "#{settings.base}/browse/#{key}"

  @doc "One line for an issue as the search returns it."
  def line(%{"key" => key, "fields" => fields}) do
    status = get_in(fields, ["status", "name"])
    type = get_in(fields, ["issuetype", "name"])
    priority = get_in(fields, ["priority", "name"])
    assignee = get_in(fields, ["assignee", "displayName"]) || "unassigned"
    meta = [status, type, priority, assignee] |> Enum.reject(&is_nil/1) |> Enum.join(", ")
    "#{key}: #{fields["summary"]} (#{meta})"
  end
end

defmodule Pepe.Plugins.JiraSearch do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Jira.Client

  @impl true
  def name, do: "jira_search"

  @impl true
  def spec do
    function(
      "jira_search",
      "Search Jira issues with a JQL query and list the matches (key, summary, status, type, priority, assignee). " <>
        "Example JQL: project = CNSUP AND status != Done ORDER BY created DESC.",
      %{
        "type" => "object",
        "properties" => %{
          "jql" => %{"type" => "string", "description" => "The JQL query."},
          "max" => %{"type" => "integer", "description" => "How many issues to return (1 to 50, default 10)."}
        },
        "required" => ["jql"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  # What a search returns was written by whoever filed the issues.
  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"jql" => jql} = args, _ctx) when is_binary(jql) and jql != "" do
    max = args["max"] |> to_int(10) |> min(50) |> max(1)

    with {:ok, settings} <- Client.settings(),
         {:ok, body} <-
           Client.get(settings, "/search/jql", jql: jql, maxResults: max, fields: "summary,status,issuetype,priority,assignee") do
      case body["issues"] do
        [_ | _] = issues -> {:ok, issues |> Enum.map_join("\n", &Client.line/1) |> Client.external()}
        _ -> {:ok, "No issues match that query."}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "jira_search needs a `jql` query."}

  defp to_int(value, _default) when is_integer(value), do: value
  defp to_int(_value, default), do: default
end

defmodule Pepe.Plugins.JiraGetIssue do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Jira.Client

  @fields "summary,status,issuetype,priority,assignee,reporter,labels,created,updated,description"

  @impl true
  def name, do: "jira_get_issue"

  @impl true
  def spec do
    function(
      "jira_get_issue",
      "Read one Jira issue: summary, status, people, labels, description and its latest comments.",
      %{
        "type" => "object",
        "properties" => %{
          "key" => %{"type" => "string", "description" => "The issue key, like CNSUP-123."},
          "comments" => %{"type" => "integer", "description" => "How many of the latest comments to include (0 to 20, default 5)."}
        },
        "required" => ["key"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"key" => key} = args, _ctx) do
    comments = if is_integer(args["comments"]), do: args["comments"] |> min(20) |> max(0), else: 5

    with {:ok, key} <- Client.issue_key(key),
         {:ok, settings} <- Client.settings(),
         {:ok, issue} <- Client.get(settings, "/issue/#{key}", fields: @fields),
         {:ok, thread} <- latest_comments(settings, key, comments) do
      {:ok, issue |> render(settings, thread) |> Client.external()}
    end
  end

  def run(_args, _ctx), do: {:error, "jira_get_issue needs a `key`."}

  defp latest_comments(_settings, _key, 0), do: {:ok, []}

  defp latest_comments(settings, key, max) do
    with {:ok, body} <- Client.get(settings, "/issue/#{key}/comment", maxResults: max, orderBy: "-created") do
      {:ok, body["comments"] |> List.wrap() |> Enum.reverse()}
    end
  end

  defp render(%{"key" => key, "fields" => f}, settings, comments) do
    header = [
      "#{key}: #{f["summary"]}",
      "Link: #{Client.browse_url(settings, key)}",
      "Status: #{get_in(f, ["status", "name"])}   Type: #{get_in(f, ["issuetype", "name"])}   Priority: #{get_in(f, ["priority", "name"]) || "none"}",
      "Assignee: #{get_in(f, ["assignee", "displayName"]) || "unassigned"}   Reporter: #{get_in(f, ["reporter", "displayName"]) || "unknown"}",
      "Labels: #{(f["labels"] || []) |> Enum.join(", ")}",
      "Created: #{f["created"]}   Updated: #{f["updated"]}"
    ]

    description = f["description"] |> Client.from_adf()
    body = if description == "", do: ["", "(no description)"], else: ["", "Description:", description]

    thread =
      case comments do
        [] -> []
        list -> ["", "Latest comments:" | Enum.map(list, &comment_line/1)]
      end

    Enum.join(header ++ body ++ thread, "\n")
  end

  defp comment_line(c), do: "[#{c["created"]}] #{get_in(c, ["author", "displayName"]) || "someone"}: #{Client.from_adf(c["body"])}"
end

defmodule Pepe.Plugins.JiraCreateIssue do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Jira.Client

  @impl true
  def name, do: "jira_create_issue"

  @impl true
  def spec do
    function(
      "jira_create_issue",
      "Create a Jira issue. Gives back its key and link. Use the project the user named; if they named none, " <>
        "the configured default project is used.",
      %{
        "type" => "object",
        "properties" => %{
          "summary" => %{"type" => "string", "description" => "The title."},
          "description" => %{"type" => "string", "description" => "The body. Blank lines split paragraphs."},
          "project" => %{"type" => "string", "description" => "Project key, like CNSUP (optional if a default is set)."},
          "issue_type" => %{"type" => "string", "description" => "Task, Bug, Story... (default Task)."},
          "labels" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Labels to add."},
          "priority" => %{"type" => "string", "description" => "Priority name, like High (optional)."}
        },
        "required" => ["summary"]
      }
    )
  end

  @impl true
  def run(%{"summary" => summary} = args, _ctx) when is_binary(summary) and summary != "" do
    project = blank(args["project"]) || Client.default_project()

    with {:ok, project} <- project(project),
         :ok <- Client.writable?(project),
         {:ok, settings} <- Client.settings(),
         {:ok, %{"key" => key}} <- Client.post(settings, "/issue", %{"fields" => fields(project, summary, args)}) do
      {:ok, "Created #{key}: #{Client.browse_url(settings, key)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "jira_create_issue needs a `summary`."}

  defp project(nil), do: {:error, "No project given and no default project is configured."}
  defp project(value), do: {:ok, value |> String.trim() |> String.upcase()}

  defp fields(project, summary, args) do
    %{
      "project" => %{"key" => project},
      "summary" => summary,
      "issuetype" => %{"name" => blank(args["issue_type"]) || "Task"}
    }
    |> put_unless_blank("description", blank(args["description"]) && Client.to_adf(args["description"]))
    |> put_unless_blank("labels", labels(args["labels"]))
    |> put_unless_blank("priority", blank(args["priority"]) && %{"name" => args["priority"]})
  end

  defp labels(list) when is_list(list),
    do: list |> Enum.filter(&is_binary/1) |> Enum.map(&String.replace(&1, " ", "-")) |> then(&if(&1 == [], do: nil, else: &1))

  defp labels(_other), do: nil

  defp put_unless_blank(map, _key, value) when value in [nil, "", []], do: map
  defp put_unless_blank(map, key, value), do: Map.put(map, key, value)

  defp blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp blank(_value), do: nil
end

defmodule Pepe.Plugins.JiraComment do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Jira.Client

  @impl true
  def name, do: "jira_comment"

  @impl true
  def spec do
    function("jira_comment", "Add a comment to a Jira issue.", %{
      "type" => "object",
      "properties" => %{
        "key" => %{"type" => "string", "description" => "The issue key, like CNSUP-123."},
        "comment" => %{"type" => "string", "description" => "The comment. Blank lines split paragraphs."}
      },
      "required" => ["key", "comment"]
    })
  end

  @impl true
  def run(%{"key" => key, "comment" => comment}, _ctx) when is_binary(comment) and comment != "" do
    with {:ok, key} <- Client.issue_key(key),
         :ok <- Client.writable?(key),
         {:ok, settings} <- Client.settings(),
         {:ok, _} <- Client.post(settings, "/issue/#{key}/comment", %{"body" => Client.to_adf(comment)}) do
      {:ok, "Commented on #{key}: #{Client.browse_url(settings, key)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "jira_comment needs a `key` and a `comment`."}
end

defmodule Pepe.Plugins.JiraTransition do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Jira.Client

  @impl true
  def name, do: "jira_transition"

  @impl true
  def spec do
    function(
      "jira_transition",
      "Move a Jira issue through its workflow (for example to In Progress or Done). Leave `to` empty to list the " <>
        "moves this issue allows right now.",
      %{
        "type" => "object",
        "properties" => %{
          "key" => %{"type" => "string", "description" => "The issue key, like CNSUP-123."},
          "to" => %{"type" => "string", "description" => "The transition or the status it leads to, like Done. Empty to list."}
        },
        "required" => ["key"]
      }
    )
  end

  @impl true
  def run(%{"key" => key} = args, _ctx) do
    with {:ok, key} <- Client.issue_key(key),
         :ok <- Client.writable?(key),
         {:ok, settings} <- Client.settings(),
         {:ok, %{"transitions" => moves}} <- Client.get(settings, "/issue/#{key}/transitions") do
      case String.trim(to_string(args["to"])) do
        "" -> {:ok, "#{key} can move to: #{names(moves)}."}
        wanted -> move(settings, key, moves, wanted)
      end
    end
  end

  def run(_args, _ctx), do: {:error, "jira_transition needs a `key`."}

  defp move(settings, key, moves, wanted) do
    case Enum.find(moves, &matches?(&1, wanted)) do
      nil ->
        {:error, "#{key} cannot move to #{inspect(wanted)} from where it is. It can move to: #{names(moves)}."}

      %{"id" => id} = found ->
        with {:ok, _} <- Client.post(settings, "/issue/#{key}/transitions", %{"transition" => %{"id" => id}}) do
          {:ok, "Moved #{key} with #{inspect(found["name"])} (now #{get_in(found, ["to", "name"]) || "updated"})."}
        end
    end
  end

  defp matches?(move, wanted) do
    wanted = String.downcase(wanted)
    String.downcase(to_string(move["name"])) == wanted or String.downcase(to_string(get_in(move, ["to", "name"]))) == wanted
  end

  defp names(moves), do: moves |> Enum.map(& &1["name"]) |> Enum.join(", ")
end
