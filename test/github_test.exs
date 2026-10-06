defmodule Pepe.Plugins.GitHubTest do
  @moduledoc """
  The GitHub plugin against a fake GitHub: what it asks for, what it sends, how it reads the
  answer, and what it refuses to do. Nothing here talks to the real service.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.GitHub.Client
  alias Pepe.Plugins.GitHubComment
  alias Pepe.Plugins.GitHubCreateIssue
  alias Pepe.Plugins.GitHubGetFile
  alias Pepe.Plugins.GitHubGetIssue
  alias Pepe.Plugins.GitHubSearch

  defmodule FakeGitHub do
    @moduledoc false
    import Plug.Conn

    def init(test), do: test

    def call(conn, test) do
      {:ok, raw, conn} = read_body(conn)
      body = if raw == "", do: nil, else: Jason.decode!(raw)
      conn = fetch_query_params(conn)
      headers = Map.new(conn.req_headers)
      send(test, {:request, conn.method, conn.request_path, conn.query_params, body, headers})

      case {conn.method, conn.request_path} do
        {"GET", "/search/issues"} ->
          json(conn, 200, %{"total_count" => 2, "items" => [item(7, "Login fails", "open", false), item(9, "Fix login", "closed", true)]})

        {"GET", "/repos/acme/app/issues/7"} ->
          json(
            conn,
            200,
            Map.merge(item(7, "Login fails", "open", false), %{
              "body" => "It crashes.",
              "comments" => 2,
              "html_url" => "https://github.com/acme/app/issues/7",
              "assignees" => [%{"login" => "ana"}],
              "created_at" => "2026-10-01",
              "updated_at" => "2026-10-02"
            })
          )

        {"GET", "/repos/acme/app/issues/9"} ->
          json(
            conn,
            200,
            Map.merge(item(9, "Fix login", "closed", true), %{
              "body" => "Fixes #7",
              "comments" => 0,
              "html_url" => "https://github.com/acme/app/pull/9",
              "assignees" => [],
              "created_at" => "2026-10-03",
              "updated_at" => "2026-10-03"
            })
          )

        {"GET", "/repos/acme/app/issues/7/comments"} ->
          json(conn, 200, [
            %{"created_at" => "2026-10-02", "user" => %{"login" => "bruno"}, "body" => "Reproduced"},
            %{"created_at" => "2026-10-02", "user" => %{"login" => "ana"}, "body" => "On it"}
          ])

        {"GET", "/repos/acme/app/pulls/9"} ->
          json(conn, 200, %{
            "state" => "closed",
            "merged" => true,
            "draft" => false,
            "head" => %{"ref" => "fix-login"},
            "base" => %{"ref" => "main"},
            "changed_files" => 3,
            "additions" => 40,
            "deletions" => 5
          })

        {"GET", "/repos/acme/app/contents/lib/app.ex"} ->
          json(conn, 200, %{
            "type" => "file",
            "size" => 12,
            "encoding" => "base64",
            "content" => Base.encode64("defmodule A do\nend\n", padding: true)
          })

        {"GET", "/repos/acme/app/contents/big.bin"} ->
          json(conn, 200, %{"type" => "file", "size" => 9_000_000, "encoding" => "none", "content" => ""})

        {"GET", "/repos/acme/app/contents/logo.png"} ->
          json(conn, 200, %{"type" => "file", "size" => 4, "encoding" => "base64", "content" => Base.encode64(<<255, 216, 255, 224>>)})

        {"GET", "/repos/acme/app/contents/lib"} ->
          json(conn, 200, [%{"type" => "file", "name" => "app.ex", "size" => 12}, %{"type" => "dir", "name" => "sub", "size" => 0}])

        {"POST", "/repos/acme/app/issues"} ->
          json(conn, 201, %{"number" => 12, "html_url" => "https://github.com/acme/app/issues/12"})

        {"POST", "/repos/acme/app/issues/7/comments"} ->
          json(conn, 201, %{"html_url" => "https://github.com/acme/app/issues/7#issuecomment-1"})

        {_, "/repos/acme/ghost/issues/1"} ->
          json(conn, 404, %{"message" => "Not Found"})

        {_, "/repos/acme/limited/issues/1"} ->
          conn |> put_resp_header("x-ratelimit-remaining", "0") |> json(403, %{"message" => "API rate limit exceeded"})

        {_, "/repos/acme/forbidden/issues/1"} ->
          json(conn, 403, %{"message" => "Resource not accessible by personal access token"})

        {"POST", "/repos/acme/bad/issues"} ->
          json(conn, 422, %{"message" => "Validation Failed", "errors" => [%{"message" => "label does not exist"}]})

        _ ->
          json(conn, 401, %{"message" => "Bad credentials"})
      end
    end

    defp json(conn, status, data), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))

    defp item(number, title, state, pr?) do
      base = %{
        "number" => number,
        "title" => title,
        "state" => state,
        "user" => %{"login" => "bruno"},
        "labels" => [%{"name" => "bug"}],
        "repository_url" => "https://api.github.com/repos/acme/app"
      }

      if pr?, do: Map.put(base, "pull_request", %{}), else: base
    end
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: {FakeGitHub, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)

    Application.put_env(:pepe_plugins, :plugin_config, %{
      "github" => %{
        "token" => "ghp_test",
        "api_url" => "http://127.0.0.1:#{port}",
        "default_repo" => "acme/app",
        "allowed_repos" => "acme/app"
      }
    })

    on_exit(fn -> Application.delete_env(:pepe_plugins, :plugin_config) end)
    :ok
  end

  describe "reading" do
    test "search sends the query with the token and GitHub's headers, and lists the matches" do
      assert {:ok, out} = GitHubSearch.run(%{"query" => "repo:acme/app is:open login", "max" => 2}, %{})

      assert_received {:request, "GET", "/search/issues", query, nil, headers}
      assert query["q"] == "repo:acme/app is:open login"
      assert query["per_page"] == "2"
      assert headers["authorization"] == "Bearer ghp_test"
      assert headers["accept"] == "application/vnd.github+json"
      assert headers["x-github-api-version"] == "2022-11-28"
      assert headers["user-agent"] == "pepe-github-plugin"

      assert out =~ "2 found, showing 2"
      assert out =~ "acme/app#7: Login fails (open, issue, by bruno, labels: bug)"
      assert out =~ "acme/app#9: Fix login (closed, pull request"
    end

    test "what comes out of GitHub is framed as external content, never as instructions" do
      {:ok, search} = GitHubSearch.run(%{"query" => "x"}, %{})
      {:ok, issue} = GitHubGetIssue.run(%{"number" => 7}, %{})
      {:ok, file} = GitHubGetFile.run(%{"path" => "lib/app.ex"}, %{})

      for out <- [search, issue, file], do: assert(out =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: github")
      assert GitHubSearch.outside_content?() and GitHubGetIssue.outside_content?() and GitHubGetFile.outside_content?()
    end

    test "an issue is read with its text and the latest comments, using the default repository" do
      assert {:ok, out} = GitHubGetIssue.run(%{"number" => 7, "comments" => 1}, %{})

      assert out =~ "acme/app#7: Login fails (open, issue, by bruno, labels: bug)"
      assert out =~ "Assignees: ana"
      assert out =~ "It crashes."
      assert out =~ "ana: On it"
      refute out =~ "Reproduced"
      assert_received {:request, "GET", "/repos/acme/app/issues/7/comments", %{"page" => "1", "per_page" => "100"}, nil, _}
    end

    test "a pull request also says whether it was merged and between which branches" do
      assert {:ok, out} = GitHubGetIssue.run(%{"repo" => "acme/app", "number" => "#9"}, %{})
      assert out =~ "Pull request: merged, fix-login into main, 3 files changed (+40 -5)"
    end

    test "a file is decoded and shown; a folder is listed; both can name a ref" do
      assert {:ok, file} = GitHubGetFile.run(%{"path" => "lib/app.ex", "ref" => "v1.2"}, %{})
      assert file =~ "defmodule A do"
      assert_received {:request, "GET", "/repos/acme/app/contents/lib/app.ex", %{"ref" => "v1.2"}, nil, _}

      assert {:ok, dir} = GitHubGetFile.run(%{"path" => "lib"}, %{})
      assert dir =~ "sub/\napp.ex (12 bytes)"
    end

    test "a file too big, or not text, is not put in front of the model" do
      assert {:error, big} = GitHubGetFile.run(%{"path" => "big.bin"}, %{})
      assert big =~ "too large"
      assert {:ok, binary} = GitHubGetFile.run(%{"path" => "logo.png"}, %{})
      assert binary =~ "not a text file"
    end

    test "a long file is cut and says so" do
      assert Client.clip(String.duplicate("a", 25_000), 20_000) =~ "[... cut, 5000 more characters]"
    end

    test "nothing that is not a repository, a number or a clean path reaches the network" do
      assert {:error, _} = GitHubGetIssue.run(%{"repo" => "../../x", "number" => 1}, %{})
      assert {:error, _} = GitHubGetIssue.run(%{"number" => "seven"}, %{})
      assert {:error, _} = GitHubGetFile.run(%{"path" => "../../etc/passwd"}, %{})
      assert {:error, _} = GitHubGetFile.run(%{"path" => "lib", "ref" => "main; rm"}, %{})
      refute_received {:request, _, _, _, _, _}
    end
  end

  describe "writing" do
    test "open an issue sends the title, text, labels and assignees, and returns the link" do
      args = %{"title" => "Crash", "body" => "Steps...", "labels" => ["bug"], "assignees" => ["ana"]}
      assert {:ok, out} = GitHubCreateIssue.run(args, %{})
      assert out == "Opened acme/app#12: https://github.com/acme/app/issues/12"

      assert_received {:request, "POST", "/repos/acme/app/issues", _, body, _}
      assert body == %{"title" => "Crash", "body" => "Steps...", "labels" => ["bug"], "assignees" => ["ana"]}
    end

    test "a comment is posted on the issue or pull request" do
      assert {:ok, out} = GitHubComment.run(%{"number" => 7, "comment" => "Fixed"}, %{})
      assert out =~ "Commented on acme/app#7"
      assert_received {:request, "POST", "/repos/acme/app/issues/7/comments", _, %{"body" => "Fixed"}, _}
    end

    test "no repository and no default says so" do
      Application.put_env(:pepe_plugins, :plugin_config, %{"github" => %{"token" => "t", "api_url" => "http://x"}})
      assert {:error, msg} = GitHubCreateIssue.run(%{"title" => "x"}, %{})
      assert msg =~ "No repository given"
    end
  end

  describe "writing is off until the repositories are listed" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, update_in(config, ["github"], &Map.delete(&1, "allowed_repos")))
      :ok
    end

    test "with no list, every write is refused before any request, and reading still works" do
      assert {:error, msg} = GitHubCreateIssue.run(%{"title" => "x"}, %{})
      assert msg =~ "Writing to GitHub is off"
      assert {:error, _} = GitHubComment.run(%{"number" => 7, "comment" => "x"}, %{})
      refute_received {:request, _, _, _, _, _}
      assert {:ok, _} = GitHubSearch.run(%{"query" => "x"}, %{})
    end

    test "a star lets it write anywhere" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["github", "allowed_repos"], "*"))
      assert {:ok, _} = GitHubComment.run(%{"repo" => "acme/app", "number" => 7, "comment" => "ok"}, %{})
    end
  end

  describe "the repository allowlist" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["github", "allowed_repos"], "Acme/App, other/*"))
      :ok
    end

    test "writing inside it works, in any letter case, and an owner/* entry covers every repository of the owner" do
      assert {:ok, _} = GitHubComment.run(%{"number" => 7, "comment" => "ok"}, %{})
      assert :ok = Client.writable?("other/anything")
    end

    test "writing outside it is refused before any request" do
      assert {:error, msg} = GitHubCreateIssue.run(%{"repo" => "acme/secret", "title" => "x"}, %{})
      assert msg =~ "may not change acme/secret"
      assert {:error, _} = GitHubComment.run(%{"repo" => "acme/secret", "number" => 1, "comment" => "x"}, %{})
      refute_received {:request, _, _, _, _, _}
    end

    test "reading is not limited by it" do
      assert {:ok, _} = GitHubSearch.run(%{"query" => "repo:acme/secret"}, %{})
    end
  end

  describe "when GitHub says no" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["github", "allowed_repos"], "*"))
      :ok
    end

    test "a repository that is missing, or private to this token" do
      assert {:error, msg} = GitHubGetIssue.run(%{"repo" => "acme/ghost", "number" => 1}, %{})
      assert msg =~ "could not find it"
    end

    test "a rate limit is told apart from a permission problem" do
      assert {:error, limited} = GitHubGetIssue.run(%{"repo" => "acme/limited", "number" => 1}, %{})
      assert limited =~ "rate limiting"
      assert {:error, forbidden} = GitHubGetIssue.run(%{"repo" => "acme/forbidden", "number" => 1}, %{})
      assert forbidden =~ "not allowed to do that: Resource not accessible"
    end

    test "a refused field names what GitHub complained about" do
      assert {:error, msg} = GitHubCreateIssue.run(%{"repo" => "acme/bad", "title" => "x"}, %{})
      assert msg =~ "Validation Failed; label does not exist"
    end

    test "a token GitHub does not accept points at the token" do
      assert {:error, msg} = GitHubGetIssue.run(%{"repo" => "acme/unknown", "number" => 1}, %{})
      assert msg =~ "did not accept the access token"
    end

    test "no settings at all says what to fill in" do
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = GitHubSearch.run(%{"query" => "x"}, %{})
      assert msg =~ "GitHub is not configured"
    end
  end
end
