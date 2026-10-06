defmodule Pepe.Plugins.JiraTest do
  @moduledoc """
  The Jira plugin against a fake Jira: what it asks for, what it sends, how it reads the answer,
  and what it refuses to do. Nothing here talks to a real Atlassian site.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.Jira.Client
  alias Pepe.Plugins.JiraComment
  alias Pepe.Plugins.JiraCreateIssue
  alias Pepe.Plugins.JiraGetIssue
  alias Pepe.Plugins.JiraSearch
  alias Pepe.Plugins.JiraTransition

  defmodule FakeJira do
    @moduledoc false
    import Plug.Conn

    def init(test), do: test

    def call(conn, test) do
      {:ok, raw, conn} = read_body(conn)
      body = if raw == "", do: nil, else: Jason.decode!(raw)
      conn = fetch_query_params(conn)
      auth = conn |> get_req_header("authorization") |> List.first()
      send(test, {:request, conn.method, conn.request_path, conn.query_params, body, auth})

      case {conn.method, conn.request_path} do
        {"GET", "/rest/api/3/search/jql"} ->
          json(conn, 200, %{"issues" => [issue("CNSUP-1", "Report does not open", "Open"), issue("CNSUP-2", "Slow login", "In Progress")]})

        {"GET", "/rest/api/3/issue/CNSUP-1"} ->
          json(conn, 200, %{
            "key" => "CNSUP-1",
            "fields" =>
              Map.merge(issue("CNSUP-1", "Report does not open", "Open")["fields"], %{
                "labels" => ["web"],
                "description" => adf("Click the report.\nNothing happens.")
              })
          })

        {"GET", "/rest/api/3/issue/CNSUP-1/comment"} ->
          json(conn, 200, %{
            "comments" => [%{"created" => "2026-10-02", "author" => %{"displayName" => "Soraya"}, "body" => adf("Looking into it")}]
          })

        {"GET", "/rest/api/3/issue/CNSUP-1/transitions"} ->
          json(conn, 200, %{
            "transitions" => [
              %{"id" => "21", "name" => "Start work", "to" => %{"name" => "In Progress"}},
              %{"id" => "31", "name" => "Finish", "to" => %{"name" => "Done"}}
            ]
          })

        {"POST", "/rest/api/3/issue"} ->
          json(conn, 201, %{"id" => "10", "key" => "CNSUP-9"})

        {"POST", "/rest/api/3/issue/CNSUP-1/comment"} ->
          json(conn, 201, %{"id" => "5"})

        {"POST", "/rest/api/3/issue/CNSUP-1/transitions"} ->
          send_resp(conn, 204, "")

        {_, "/rest/api/3/issue/NOPE-1"} ->
          json(conn, 404, %{"errorMessages" => ["Issue does not exist"], "errors" => %{}})

        {"POST", "/rest/api/3/issue/BAD-1/comment"} ->
          json(conn, 400, %{"errorMessages" => [], "errors" => %{"comment" => "is required"}})

        _ ->
          json(conn, 401, %{})
      end
    end

    defp json(conn, status, map), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(map))

    defp issue(key, summary, status) do
      %{
        "key" => key,
        "fields" => %{
          "summary" => summary,
          "status" => %{"name" => status},
          "issuetype" => %{"name" => "Bug"},
          "priority" => %{"name" => "High"},
          "assignee" => %{"displayName" => "Ana"},
          "reporter" => %{"displayName" => "Cliente"},
          "created" => "2026-10-01",
          "updated" => "2026-10-02"
        }
      }
    end

    defp adf(text) do
      lines = text |> String.split("\n") |> Enum.map(&%{"type" => "text", "text" => &1}) |> Enum.intersperse(%{"type" => "hardBreak"})
      %{"type" => "doc", "version" => 1, "content" => [%{"type" => "paragraph", "content" => lines}]}
    end
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: {FakeJira, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)

    Application.put_env(:pepe_plugins, :plugin_config, %{
      "jira" => %{
        "site" => "http://127.0.0.1:#{port}",
        "email" => "me@example.com",
        "api_token" => "tok",
        "default_project" => "CNSUP",
        "allowed_projects" => "CNSUP"
      }
    })

    on_exit(fn -> Application.delete_env(:pepe_plugins, :plugin_config) end)
    :ok
  end

  describe "reading" do
    test "search sends the JQL with the account's basic auth and lists the matches" do
      assert {:ok, out} = JiraSearch.run(%{"jql" => "project = CNSUP", "max" => 2}, %{})

      assert_received {:request, "GET", "/rest/api/3/search/jql", query, nil, auth}
      assert query["jql"] == "project = CNSUP"
      assert query["maxResults"] == "2"
      assert auth == "Basic " <> Base.encode64("me@example.com:tok")

      assert out =~ "CNSUP-1: Report does not open (Open, Bug, High, Ana)"
      assert out =~ "CNSUP-2: Slow login (In Progress"
    end

    test "what comes out of Jira is framed as external content, never as instructions" do
      {:ok, search} = JiraSearch.run(%{"jql" => "x"}, %{})
      {:ok, issue} = JiraGetIssue.run(%{"key" => "cnsup-1"}, %{})

      assert search =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: jira"
      assert issue =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: jira"
      assert JiraSearch.outside_content?()
      assert JiraGetIssue.outside_content?()
    end

    test "get_issue reads the description (from Jira's rich text) and the latest comments" do
      assert {:ok, out} = JiraGetIssue.run(%{"key" => "CNSUP-1", "comments" => 3}, %{})

      assert out =~ "CNSUP-1: Report does not open"
      assert out =~ "Labels: web"
      assert out =~ "Click the report.\nNothing happens."
      assert out =~ "Soraya: Looking into it"
      assert_received {:request, "GET", "/rest/api/3/issue/CNSUP-1/comment", %{"maxResults" => "3"}, nil, _}
    end

    test "comments: 0 does not ask for them at all" do
      assert {:ok, _} = JiraGetIssue.run(%{"key" => "CNSUP-1", "comments" => 0}, %{})
      refute_received {:request, "GET", "/rest/api/3/issue/CNSUP-1/comment", _, _, _}
    end

    test "a key that is not a key is refused before any request" do
      assert {:error, msg} = JiraGetIssue.run(%{"key" => "../../myself"}, %{})
      assert msg =~ "not a Jira issue key"
      refute_received {:request, _, _, _, _, _}
    end
  end

  describe "writing" do
    test "create sends the project, type and an Atlassian Document description, and returns the link" do
      args = %{
        "summary" => "Report broken",
        "description" => "First.\n\nSecond.",
        "issue_type" => "Bug",
        "labels" => ["web app"],
        "priority" => "High"
      }

      assert {:ok, out} = JiraCreateIssue.run(args, %{})
      assert out =~ "Created CNSUP-9: http://127.0.0.1:"
      assert out =~ "/browse/CNSUP-9"

      assert_received {:request, "POST", "/rest/api/3/issue", _, %{"fields" => fields}, _}
      assert fields["project"] == %{"key" => "CNSUP"}
      assert fields["issuetype"] == %{"name" => "Bug"}
      assert fields["labels"] == ["web-app"]
      assert fields["priority"] == %{"name" => "High"}
      assert %{"type" => "doc", "content" => [_, _]} = fields["description"]
    end

    test "create without a project and without a default says so" do
      Application.put_env(:pepe_plugins, :plugin_config, %{"jira" => %{"site" => "http://x", "email" => "a", "api_token" => "t"}})
      assert {:error, msg} = JiraCreateIssue.run(%{"summary" => "x"}, %{})
      assert msg =~ "No project given"
    end

    test "comment posts an Atlassian Document body" do
      assert {:ok, out} = JiraComment.run(%{"key" => "CNSUP-1", "comment" => "Fixed in 1.2"}, %{})
      assert out =~ "Commented on CNSUP-1"

      assert_received {:request, "POST", "/rest/api/3/issue/CNSUP-1/comment", _, %{"body" => %{"type" => "doc"} = doc}, _}
      assert get_in(doc, ["content", Access.at(0), "content", Access.at(0), "text"]) == "Fixed in 1.2"
    end

    test "transition with no target lists what is allowed" do
      assert {:ok, out} = JiraTransition.run(%{"key" => "CNSUP-1"}, %{})
      assert out =~ "Start work, Finish"
      refute_received {:request, "POST", _, _, _, _}
    end

    test "transition finds the move by its name or by the status it leads to" do
      assert {:ok, out} = JiraTransition.run(%{"key" => "CNSUP-1", "to" => "done"}, %{})
      assert out =~ "Moved CNSUP-1 with \"Finish\" (now Done)"
      assert_received {:request, "POST", "/rest/api/3/issue/CNSUP-1/transitions", _, %{"transition" => %{"id" => "31"}}, _}
    end

    test "transition to somewhere it cannot go says where it can" do
      assert {:error, msg} = JiraTransition.run(%{"key" => "CNSUP-1", "to" => "Archived"}, %{})
      assert msg =~ "cannot move to \"Archived\""
      assert msg =~ "Start work, Finish"
    end
  end

  describe "writing is off until the projects are listed" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, update_in(config, ["jira"], &Map.delete(&1, "allowed_projects")))
      :ok
    end

    test "with no list, every write is refused before any request, and reading still works" do
      assert {:error, msg} = JiraComment.run(%{"key" => "CNSUP-1", "comment" => "x"}, %{})
      assert msg =~ "Writing to Jira is off"
      assert {:error, _} = JiraCreateIssue.run(%{"summary" => "x"}, %{})
      assert {:error, _} = JiraTransition.run(%{"key" => "CNSUP-1", "to" => "Done"}, %{})
      refute_received {:request, _, _, _, _, _}
      assert {:ok, _} = JiraSearch.run(%{"jql" => "project = CNSUP"}, %{})
    end

    test "a star lets it write anywhere" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["jira", "allowed_projects"], "*"))
      assert {:ok, _} = JiraComment.run(%{"key" => "CNSUP-1", "comment" => "ok"}, %{})
    end
  end

  describe "the project allowlist" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      put_in(config, ["jira", "allowed_projects"], "ops, CNSUP") |> then(&Application.put_env(:pepe_plugins, :plugin_config, &1))
      :ok
    end

    test "writing inside it works, in any letter case" do
      assert {:ok, _} = JiraComment.run(%{"key" => "cnsup-1", "comment" => "ok"}, %{})
    end

    test "writing outside it is refused before any request" do
      assert {:error, msg} = JiraComment.run(%{"key" => "SECRET-1", "comment" => "x"}, %{})
      assert msg =~ "may not change project SECRET"
      assert {:error, _} = JiraCreateIssue.run(%{"summary" => "x", "project" => "SECRET"}, %{})
      assert {:error, _} = JiraTransition.run(%{"key" => "SECRET-1", "to" => "Done"}, %{})
      refute_received {:request, _, _, _, _, _}
    end

    test "reading is not limited by it" do
      assert {:ok, _} = JiraSearch.run(%{"jql" => "project = SECRET"}, %{})
    end
  end

  describe "when Jira says no" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["jira", "allowed_projects"], "*"))
      :ok
    end

    test "a missing issue" do
      assert {:error, msg} = JiraGetIssue.run(%{"key" => "NOPE-1"}, %{})
      assert msg =~ "could not find it"
    end

    test "a bad request names the field Jira complained about" do
      assert {:error, msg} = JiraComment.run(%{"key" => "BAD-1", "comment" => "x"}, %{})
      assert msg =~ "comment: is required"
    end

    test "a login Jira does not accept points at the e-mail and the token" do
      # The fake answers 401 to anything it does not know.
      assert {:error, msg} = JiraTransition.run(%{"key" => "CNSUP-77"}, %{})
      assert msg =~ "did not accept the e-mail and API token"
    end

    test "no settings at all says what to fill in, and makes no request" do
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = JiraSearch.run(%{"jql" => "x"}, %{})
      assert msg =~ "Jira is not configured"
      assert msg =~ "API token"
    end
  end

  describe "Jira's rich text" do
    test "reads paragraphs, lists, mentions and links" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "Hi "}, %{"type" => "mention", "attrs" => %{"text" => "@ana"}}]
          },
          %{
            "type" => "bulletList",
            "content" => [
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "one"}]}]}
            ]
          },
          %{"type" => "paragraph", "content" => [%{"type" => "inlineCard", "attrs" => %{"url" => "https://x.test/a"}}]}
        ]
      }

      assert Client.from_adf(doc) == "Hi @ana\n- one\nhttps://x.test/a"
    end

    test "nothing, a plain string and an empty document all read as text" do
      assert Client.from_adf(nil) == ""
      assert Client.from_adf("plain") == "plain"
      assert Client.from_adf(%{"type" => "doc", "content" => []}) == ""
    end

    test "text becomes paragraphs split on blank lines, with single newlines kept as breaks" do
      assert %{"content" => [first, second]} = Client.to_adf("a\nb\n\nc")
      assert first["content"] == [%{"type" => "text", "text" => "a"}, %{"type" => "hardBreak"}, %{"type" => "text", "text" => "b"}]
      assert second["content"] == [%{"type" => "text", "text" => "c"}]
    end
  end
end
