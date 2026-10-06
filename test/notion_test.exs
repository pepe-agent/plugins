defmodule Pepe.Plugins.NotionTest do
  @moduledoc """
  The Notion plugin against a fake Notion: what it asks for, what it sends, how it reads pages and
  properties, and what it refuses to do. Nothing here talks to the real service.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.Notion.Client
  alias Pepe.Plugins.NotionAppend
  alias Pepe.Plugins.NotionCreatePage
  alias Pepe.Plugins.NotionGetPage
  alias Pepe.Plugins.NotionQueryDatabase
  alias Pepe.Plugins.NotionSearch

  @page "a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90"
  @page_compact "a1b2c3d4e5f60718293a4b5c6d7e8f90"
  @db "11111111-2222-3333-4444-555555555555"
  @ghost "00000000-0000-0000-0000-000000000000"

  defmodule FakeNotion do
    @moduledoc false
    import Plug.Conn

    @page "a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90"
    @db "11111111-2222-3333-4444-555555555555"

    def init(test), do: test

    def call(conn, test) do
      {:ok, raw, conn} = read_body(conn)
      body = if raw == "", do: nil, else: Jason.decode!(raw)
      conn = fetch_query_params(conn)
      send(test, {:request, conn.method, conn.request_path, conn.query_params, body, Map.new(conn.req_headers)})

      case {conn.method, conn.request_path} do
        {"POST", "/v1/search"} ->
          json(conn, 200, %{
            "results" => [
              page(),
              %{
                "object" => "database",
                "id" => @db,
                "title" => [text("Tasks")],
                "url" => "https://notion.so/tasks",
                "last_edited_time" => "2026-10-02T10:00:00Z"
              }
            ]
          })

        {"GET", "/v1/pages/" <> @page} ->
          json(conn, 200, page())

        {"GET", "/v1/blocks/" <> @page <> "/children"} ->
          json(conn, 200, %{
            "results" => [
              block("heading_1", %{"rich_text" => [text("Plan")]}),
              block("paragraph", %{"rich_text" => [text("Ship it "), text("soon")]}),
              block("to_do", %{"rich_text" => [text("Write docs")], "checked" => true}),
              block("bulleted_list_item", %{"rich_text" => [text("Parent")]}, "child-1"),
              block("code", %{"rich_text" => [text("IO.puts(1)")], "language" => "elixir"}),
              block("child_page", %{"title" => "Sub page"}, nil, "sub-1")
            ],
            "has_more" => false
          })

        {"GET", "/v1/blocks/child-1/children"} ->
          json(conn, 200, %{"results" => [block("paragraph", %{"rich_text" => [text("Nested line")]})], "has_more" => false})

        {"POST", "/v1/databases/" <> @db <> "/query"} ->
          json(conn, 200, %{"results" => [page(), page()]})

        {"GET", "/v1/databases/" <> @db} ->
          json(conn, 200, %{"properties" => %{"Name" => %{"type" => "title"}, "Status" => %{"type" => "status"}}})

        {"POST", "/v1/pages"} ->
          json(conn, 200, %{"id" => "new", "url" => "https://notion.so/new-page"})

        {"PATCH", "/v1/blocks/" <> @page <> "/children"} ->
          json(conn, 200, %{"results" => []})

        {_, "/v1/pages/00000000-0000-0000-0000-000000000000"} ->
          json(conn, 404, %{"code" => "object_not_found", "message" => "Could not find page"})

        {_, "/v1/pages/99999999-0000-0000-0000-000000000000"} ->
          conn |> put_resp_header("retry-after", "7") |> json(429, %{"message" => "rate_limited"})

        {"POST", "/v1/search-bad"} ->
          json(conn, 400, %{"message" => "body failed validation"})

        _ ->
          json(conn, 401, %{"message" => "API token is invalid."})
      end
    end

    defp json(conn, status, data), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))

    defp text(content), do: %{"type" => "text", "plain_text" => content}

    defp block(type, data, id \\ nil, child_id \\ nil) do
      %{"object" => "block", "id" => child_id || id || "b-#{type}", "type" => type, "has_children" => id != nil, type => data}
    end

    defp page do
      %{
        "object" => "page",
        "id" => @page,
        "url" => "https://www.notion.so/Roadmap-a1b2c3d4e5f60718293a4b5c6d7e8f90",
        "last_edited_time" => "2026-10-02T10:00:00Z",
        "properties" => %{
          "Name" => %{"type" => "title", "title" => [text("Roadmap")]},
          "Status" => %{"type" => "status", "status" => %{"name" => "In progress"}},
          "Owner" => %{"type" => "people", "people" => [%{"name" => "Ana"}]},
          "Tags" => %{"type" => "multi_select", "multi_select" => [%{"name" => "q4"}, %{"name" => "web"}]},
          "Due" => %{"type" => "date", "date" => %{"start" => "2026-11-01", "end" => nil}},
          "Done" => %{"type" => "checkbox", "checkbox" => false},
          "Notes" => %{"type" => "rich_text", "rich_text" => []},
          "Estimate" => %{"type" => "number", "number" => 5}
        }
      }
    end
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: {FakeNotion, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)

    Application.put_env(:pepe_plugins, :plugin_config, %{
      "notion" => %{"token" => "ntn_test", "api_url" => "http://127.0.0.1:#{port}", "writes" => "yes"}
    })

    on_exit(fn -> Application.delete_env(:pepe_plugins, :plugin_config) end)
    :ok
  end

  describe "ids" do
    test "an id, an id without dashes and the address of a page all become the same id" do
      assert {:ok, @page} = Client.id(@page)
      assert {:ok, @page} = Client.id(@page_compact)
      assert {:ok, @page} = Client.id("https://www.notion.so/workspace/My-Roadmap-#{@page_compact}?pvs=4")
      assert {:ok, @page} = Client.id(String.upcase(@page_compact))
    end

    test "anything else is refused before a request" do
      assert {:error, msg} = NotionGetPage.run(%{"page" => "../../users"}, %{})
      assert msg =~ "not a Notion page or database id"
      refute_received {:request, _, _, _, _, _}
    end
  end

  describe "reading" do
    test "search sends the query and a filter, with the token and Notion's version header" do
      assert {:ok, out} = NotionSearch.run(%{"query" => "road", "kind" => "page", "max" => 5}, %{})

      assert_received {:request, "POST", "/v1/search", _, body, headers}
      assert body["query"] == "road"
      assert body["filter"] == %{"property" => "object", "value" => "page"}
      assert body["page_size"] == 5
      assert headers["authorization"] == "Bearer ntn_test"
      assert headers["notion-version"] == "2022-06-28"

      assert out =~ "page: Roadmap (#{@page}, edited 2026-10-02)"
      assert out =~ "database: Tasks (#{@db}"
    end

    test "what comes out of Notion is framed as external content, never as instructions" do
      {:ok, search} = NotionSearch.run(%{}, %{})
      {:ok, page} = NotionGetPage.run(%{"page" => @page}, %{})
      {:ok, rows} = NotionQueryDatabase.run(%{"database" => @db}, %{})

      for out <- [search, page, rows], do: assert(out =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: notion")
      assert NotionSearch.outside_content?() and NotionGetPage.outside_content?() and NotionQueryDatabase.outside_content?()
    end

    test "a page is read with its properties and its content as text" do
      assert {:ok, out} = NotionGetPage.run(%{"page" => "https://www.notion.so/Roadmap-#{@page_compact}"}, %{})

      assert out =~ "Roadmap (#{@page})"
      assert out =~ "Status: In progress"
      assert out =~ "Owner: Ana"
      assert out =~ "Tags: q4, web"
      assert out =~ "Due: 2026-11-01"
      assert out =~ "Estimate: 5"
      refute out =~ "Notes:"

      assert out =~ "# Plan"
      assert out =~ "Ship it soon"
      assert out =~ "[x] Write docs"
      assert out =~ "- Parent\n  Nested line"
      assert out =~ "```elixir\nIO.puts(1)\n```"
      assert out =~ "[page: Sub page] (sub-1)"
    end

    test "a database is listed row by row" do
      assert {:ok, out} =
               NotionQueryDatabase.run(
                 %{"database" => @db, "filter" => %{"property" => "Status", "status" => %{"equals" => "Done"}}, "max" => 2},
                 %{}
               )

      assert_received {:request, "POST", "/v1/databases/" <> _, _, body, _}
      assert body["page_size"] == 2
      assert body["filter"]["property"] == "Status"
      assert out =~ "Status: In progress"
    end
  end

  describe "writing" do
    test "create under a page sends a title and the text as paragraphs, and returns the link" do
      assert {:ok, out} = NotionCreatePage.run(%{"parent" => @page, "title" => "Notes", "content" => "One.\n\nTwo."}, %{})
      assert out =~ "https://notion.so/new-page"

      assert_received {:request, "POST", "/v1/pages", _, body, _}
      assert body["parent"] == %{"page_id" => @page}
      assert body["properties"] == %{"title" => %{"title" => [%{"type" => "text", "text" => %{"content" => "Notes"}}]}}
      assert [%{"type" => "paragraph"}, %{"type" => "paragraph"}] = body["children"]
    end

    test "create in a database finds the title property by its own name" do
      assert {:ok, _} = NotionCreatePage.run(%{"parent" => @db, "parent_type" => "database", "title" => "Task"}, %{})

      assert_received {:request, "POST", "/v1/pages", _, body, _}
      assert body["parent"] == %{"database_id" => @db}
      assert Map.keys(body["properties"]) == ["Name"]
      refute Map.has_key?(body, "children")
    end

    test "appending sends paragraphs, and a very long one is split to fit Notion's limit" do
      assert {:ok, _} = NotionAppend.run(%{"page" => @page, "text" => String.duplicate("a", 4500)}, %{})

      assert_received {:request, "PATCH", "/v1/blocks/" <> _, _, %{"children" => blocks}, _}
      sizes = Enum.map(blocks, &(get_in(&1, ["paragraph", "rich_text", Access.at(0), "text", "content"]) |> String.length()))
      assert sizes == [2000, 2000, 500]
    end
  end

  describe "writing is off until it is turned on" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["notion", "writes"], "no"))
      :ok
    end

    test "every write is refused before any request, and reading still works" do
      assert {:error, msg} = NotionCreatePage.run(%{"parent" => @page, "title" => "x"}, %{})
      assert msg =~ "Writing to Notion is off"
      assert {:error, _} = NotionAppend.run(%{"page" => @page, "text" => "x"}, %{})
      refute_received {:request, _, _, _, _, _}
      assert {:ok, _} = NotionGetPage.run(%{"page" => @page}, %{})
    end

    test "leaving the setting empty is the same as no" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, update_in(config, ["notion"], &Map.delete(&1, "writes")))
      assert {:error, _} = NotionAppend.run(%{"page" => @page, "text" => "x"}, %{})
    end
  end

  describe "when Notion says no" do
    test "a page that was not shared with the integration says how to share it" do
      assert {:error, msg} = NotionGetPage.run(%{"page" => @ghost}, %{})
      assert msg =~ "has to be shared with the integration"
    end

    test "a rate limit says how long to wait, at once, without sleeping through it" do
      {micros, result} = :timer.tc(fn -> NotionGetPage.run(%{"page" => "99999999-0000-0000-0000-000000000000"}, %{}) end)
      assert {:error, msg} = result
      assert msg =~ "rate limiting"
      assert msg =~ "7 seconds"
      assert micros < 2_000_000
      assert_received {:request, "GET", _, _, _, _}
      refute_received {:request, "GET", _, _, _, _}
    end

    test "a token Notion does not accept points at the token" do
      # The fake answers 401 to anything it does not know.
      assert {:error, msg} = NotionGetPage.run(%{"page" => "22222222-0000-0000-0000-000000000000"}, %{})
      assert msg =~ "did not accept the integration token"
    end

    test "no settings at all says what to fill in" do
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = NotionSearch.run(%{}, %{})
      assert msg =~ "Notion is not configured"
    end
  end

  describe "properties" do
    test "formulas, relations, files and ids read as text, and empty values are left out" do
      page = %{
        "properties" => %{
          "Calc" => %{"type" => "formula", "formula" => %{"type" => "number", "number" => 42}},
          "Links" => %{"type" => "relation", "relation" => [%{"id" => "a"}, %{"id" => "b"}]},
          "Docs" => %{"type" => "files", "files" => [%{}]},
          "Code" => %{"type" => "unique_id", "unique_id" => %{"prefix" => "TSK", "number" => 7}},
          "Empty" => %{"type" => "select", "select" => nil}
        }
      }

      assert Client.properties(page) == ["Calc: 42", "Code: TSK7", "Docs: 1 file(s)", "Links: 2 linked"]
    end
  end
end
