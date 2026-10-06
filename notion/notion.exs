# Notion tools for Pepe, as a drop-in plugin.
#
# Five tools: search, read a page (its properties and its content), list the rows of a database,
# create a page, and add text to a page. Each is an ordinary Pepe tool, so an agent holds exactly
# the ones it is given, and every write still passes the permission gate.
#
# Auth is an internal integration token. A Notion integration sees only the pages that were shared
# with it (the page's "Connections" menu), so that is also what limits it. Settings come from the
# plugin's Configure dialog, falling back to environment variables:
#
#   * token  / NOTION_TOKEN   the integration token
#   * writes / NOTION_WRITES  "yes" to let the agent create pages and add text; anything else = read only
#
# NOTION_API_URL overrides the address (for a proxy or a test); it is not a normal setting.

defmodule Pepe.Plugins.Notion.Client do
  @moduledoc """
  Settings, the HTTP calls, and the conversions between Notion's blocks and plain text.
  """

  @version "2022-06-28"
  @max_text 2000
  @max_blocks_per_call 100

  # ---- settings ------------------------------------------------------------------------

  @doc "The connection settings, or `{:error, message}` naming what is missing."
  def settings do
    case setting("token", "NOTION_TOKEN") do
      nil ->
        {:error, "Notion is not configured. Set the integration token under Plugins -> Configure (or the NOTION_TOKEN env var)."}

      token ->
        base = (setting("api_url", "NOTION_API_URL") || "https://api.notion.com") |> String.trim() |> String.trim_trailing("/")
        {:ok, %{base: base, token: token}}
    end
  end

  @doc "Writing is off until the operator turns it on."
  def writable? do
    if setting("writes", "NOTION_WRITES") |> to_string() |> String.downcase() == "yes",
      do: :ok,
      else: {:error, "Writing to Notion is off. Set \"Allow writing\" to yes under Plugins -> Configure."}
  end

  defp setting(key, env_key), do: Pepe.Plugins.config("notion", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # ---- ids -------------------------------------------------------------------------------

  @doc "A page or database id, from the id itself or from the address of its page, as Notion writes it."
  def id(value) do
    compact = value |> to_string() |> String.trim() |> String.split(["?", "#"]) |> hd() |> String.replace("-", "")

    case Regex.run(~r/([0-9a-fA-F]{32})\z/, compact) do
      [_, hex] ->
        hex = String.downcase(hex)

        {:ok,
         Enum.join(
           [
             String.slice(hex, 0, 8),
             String.slice(hex, 8, 4),
             String.slice(hex, 12, 4),
             String.slice(hex, 16, 4),
             String.slice(hex, 20, 12)
           ],
           "-"
         )}

      _ ->
        {:error, "#{inspect(value)} is not a Notion page or database id (or the address of one)."}
    end
  end

  def blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  def blank(_value), do: nil

  # ---- http ----------------------------------------------------------------------------

  def get(settings, path, params \\ []), do: request(settings, :get, path, params: params)
  def post(settings, path, body), do: request(settings, :post, path, json: body)
  def patch(settings, path, body), do: request(settings, :patch, path, json: body)

  defp request(settings, method, path, opts) do
    opts =
      Keyword.merge(
        [
          method: method,
          url: settings.base <> path,
          auth: {:bearer, settings.token},
          headers: [{"notion-version", @version}, {"accept", "application/json"}],
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
      {:error, reason} -> {:error, "Could not reach Notion: #{inspect(reason)}"}
    end
  end

  defp explain(401, _body, _response), do: "Notion did not accept the integration token. Check that it is current."

  defp explain(403, _body, _response), do: "Notion says this integration is not allowed to do that (check its capabilities)."

  defp explain(404, _body, _response),
    do: "Notion could not find it. The page or database has to be shared with the integration (its Connections menu)."

  defp explain(429, _body, response) do
    wait = response |> Req.Response.get_header("retry-after") |> List.first()
    "Notion is rate limiting this integration. Try again#{if wait, do: " in #{wait} seconds", else: " in a moment"}."
  end

  defp explain(status, %{"message" => message}, _response), do: "Notion refused it (#{status}): #{message}"
  defp explain(status, _body, _response), do: "Notion answered with an error (#{status})."

  # ---- reading: text, properties, blocks ---------------------------------------------------

  @doc "Notion's rich text as plain text."
  def rich(list) when is_list(list), do: Enum.map_join(list, "", &(&1["plain_text"] || ""))
  def rich(_other), do: ""

  @doc "The title of a page (its title property) or of a database."
  def title(%{"object" => "database", "title" => title}), do: rich(title)

  def title(%{"properties" => %{} = properties}) do
    properties |> Map.values() |> Enum.find_value("", fn p -> if p["type"] == "title", do: rich(p["title"]) end)
  end

  def title(%{"title" => title}), do: rich(title)
  def title(_other), do: ""

  @doc "One line for a search result or a row."
  def line(%{"object" => object, "id" => id} = item) do
    title = title(item)
    edited = item["last_edited_time"] && ", edited #{String.slice(item["last_edited_time"], 0, 10)}"
    "#{object}: #{if title == "", do: "(untitled)", else: title} (#{id}#{edited})#{item["url"] && "\n  " <> item["url"]}"
  end

  @doc "A page's properties as `Name: value` lines (empty ones left out, the title included)."
  def properties(%{"properties" => %{} = properties}) do
    properties
    |> Enum.map(fn {name, property} -> {name, value(property)} end)
    |> Enum.reject(fn {_name, value} -> value in [nil, ""] end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, value} -> "#{name}: #{value}" end)
  end

  def properties(_other), do: []

  defp value(%{"type" => type} = property) do
    data = property[type]

    case type do
      t when t in ["title", "rich_text"] -> rich(data)
      "number" -> data && to_string(data)
      t when t in ["select", "status"] -> data && data["name"]
      "multi_select" -> Enum.map_join(List.wrap(data), ", ", & &1["name"])
      "date" -> data && [data["start"], data["end"]] |> Enum.reject(&is_nil/1) |> Enum.join(" to ")
      "checkbox" -> to_string(data)
      t when t in ["url", "email", "phone_number", "created_time", "last_edited_time"] -> data
      "people" -> Enum.map_join(List.wrap(data), ", ", &(&1["name"] || &1["id"]))
      t when t in ["created_by", "last_edited_by"] -> data && data["name"]
      "relation" -> if(List.wrap(data) == [], do: nil, else: "#{length(data)} linked")
      "files" -> if(List.wrap(data) == [], do: nil, else: "#{length(data)} file(s)")
      "formula" -> data && to_string(data[data["type"]])
      "unique_id" -> data && "#{data["prefix"]}#{data["number"]}"
      _ -> nil
    end
  end

  defp value(_other), do: nil

  @doc "Read a page's content as text lines, a few levels deep, within a budget of requests."
  def content(settings, id, depth \\ 0, budget \\ 12) do
    case fetch_children(settings, id, nil, [], 0) do
      {:ok, blocks} -> render_blocks(settings, blocks, depth, budget - 1, [])
      {:error, _} = error -> error
    end
  end

  # Up to three pages of a hundred blocks: enough for a page, bounded for a long one.
  defp fetch_children(settings, id, cursor, acc, pages) do
    params = [page_size: 100] ++ if(cursor, do: [start_cursor: cursor], else: [])

    with {:ok, body} <- get(settings, "/v1/blocks/#{id}/children", params) do
      acc = acc ++ List.wrap(body["results"])

      if body["has_more"] && pages < 2,
        do: fetch_children(settings, id, body["next_cursor"], acc, pages + 1),
        else: {:ok, acc}
    end
  end

  defp render_blocks(_settings, [], _depth, budget, lines), do: {:ok, Enum.reverse(lines), budget}

  defp render_blocks(settings, [block | rest], depth, budget, lines) do
    indent = String.duplicate("  ", depth)
    own = block |> block_text() |> List.wrap() |> Enum.reject(&(&1 in [nil, ""])) |> Enum.map(&(indent <> &1))
    lines = Enum.reverse(own) ++ lines

    if block["has_children"] && depth < 2 && budget > 0 && block["type"] not in ["child_page", "child_database"] do
      case content(settings, block["id"], depth + 1, budget) do
        {:ok, inner, left} -> render_blocks(settings, rest, depth, left, Enum.reverse(inner) ++ lines)
        {:error, _} = error -> error
      end
    else
      render_blocks(settings, rest, depth, budget, lines)
    end
  end

  defp block_text(%{"type" => type} = block) do
    data = block[type] || %{}
    text = rich(data["rich_text"])

    case type do
      "paragraph" -> text
      "heading_1" -> "# " <> text
      "heading_2" -> "## " <> text
      "heading_3" -> "### " <> text
      "bulleted_list_item" -> "- " <> text
      "numbered_list_item" -> "1. " <> text
      "to_do" -> if(data["checked"], do: "[x] ", else: "[ ] ") <> text
      t when t in ["toggle", "quote"] -> "> " <> text
      "callout" -> "! " <> text
      "code" -> "```#{data["language"]}\n#{text}\n```"
      "divider" -> "---"
      "equation" -> data["expression"]
      "table_row" -> data["cells"] |> List.wrap() |> Enum.map_join(" | ", &rich/1)
      "child_page" -> "[page: #{data["title"]}] (#{block["id"]})"
      "child_database" -> "[database: #{data["title"]}] (#{block["id"]})"
      t when t in ["bookmark", "embed", "link_preview"] -> data["url"]
      t when t in ["image", "file", "pdf", "video", "audio"] -> "[#{t}] " <> rich(data["caption"])
      _ -> nil
    end
  end

  @doc """
  Text that came out of Notion is written by whoever can edit the page, so it reaches the model
  framed as quoted material, never as instructions.
  """
  def external(text) do
    Pepe.Security.ExternalContent.mark_untrusted("notion", Pepe.Security.ExternalContent.sanitize(text))
  end

  @doc "Cut a text to a length, saying so when it was cut."
  def clip(text, max) do
    text = to_string(text)
    if String.length(text) > max, do: String.slice(text, 0, max) <> "\n[... cut, #{String.length(text) - max} more characters]", else: text
  end

  # ---- writing: text as blocks -------------------------------------------------------------

  @doc "Plain text as paragraph blocks: blank lines split paragraphs, and a long one is split to fit Notion's limit."
  def paragraphs(text) do
    text
    |> to_string()
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.flat_map(&chunks/1)
    |> Enum.take(@max_blocks_per_call)
    |> Enum.map(fn chunk ->
      %{"object" => "block", "type" => "paragraph", "paragraph" => %{"rich_text" => [%{"type" => "text", "text" => %{"content" => chunk}}]}}
    end)
  end

  defp chunks(text) do
    text |> String.graphemes() |> Enum.chunk_every(@max_text) |> Enum.map(&Enum.join/1)
  end
end

defmodule Pepe.Plugins.NotionSearch do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Notion.Client

  @impl true
  def name, do: "notion_search"

  @impl true
  def spec do
    function(
      "notion_search",
      "Search the Notion pages and databases that were shared with the integration, by title. Gives back their " <>
        "titles, ids and links. Leave the query empty to list the most recently edited.",
      %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Words to look for in titles (optional)."},
          "kind" => %{"type" => "string", "enum" => ["page", "database"], "description" => "Only pages, or only databases (optional)."},
          "max" => %{"type" => "integer", "description" => "How many to return (1 to 20, default 10)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true

  # Titles are written by whoever can edit the pages.
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(20) |> max(1), else: 10

    body =
      %{"page_size" => max, "sort" => %{"direction" => "descending", "timestamp" => "last_edited_time"}}
      |> put("query", Client.blank(args["query"]))
      |> put("filter", if(args["kind"] in ["page", "database"], do: %{"property" => "object", "value" => args["kind"]}))

    with {:ok, settings} <- Client.settings(),
         {:ok, found} <- Client.post(settings, "/v1/search", body) do
      case found["results"] do
        [_ | _] = results -> {:ok, results |> Enum.map_join("\n", &Client.line/1) |> Client.external()}
        _ -> {:ok, "Nothing matches (only what was shared with the integration can be found)."}
      end
    end
  end

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end

defmodule Pepe.Plugins.NotionGetPage do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Notion.Client

  @max_chars 20_000

  @impl true
  def name, do: "notion_get_page"

  @impl true
  def spec do
    function(
      "notion_get_page",
      "Read a Notion page: its properties and its content as text. Takes the page's id or its address.",
      %{
        "type" => "object",
        "properties" => %{"page" => %{"type" => "string", "description" => "The page id, or the address of the page."}},
        "required" => ["page"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"page" => page}, _ctx) do
    with {:ok, id} <- Client.id(page),
         {:ok, settings} <- Client.settings(),
         {:ok, found} <- Client.get(settings, "/v1/pages/#{id}"),
         {:ok, lines, _budget} <- Client.content(settings, id) do
      head = ["#{Client.title(found) |> empty("(untitled)")} (#{found["id"]})", found["url"] | Client.properties(found)]
      body = if lines == [], do: ["", "(the page has no text)"], else: ["", Enum.join(lines, "\n")]
      {:ok, head |> Enum.reject(&is_nil/1) |> Kernel.++(body) |> Enum.join("\n") |> Client.clip(@max_chars) |> Client.external()}
    end
  end

  def run(_args, _ctx), do: {:error, "notion_get_page needs a `page` (its id or address)."}

  defp empty("", fallback), do: fallback
  defp empty(text, _fallback), do: text
end

defmodule Pepe.Plugins.NotionQueryDatabase do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Notion.Client

  @impl true
  def name, do: "notion_query_database"

  @impl true
  def spec do
    function(
      "notion_query_database",
      "List the rows of a Notion database with their properties. Optionally narrow them with a Notion filter object, " <>
        "for example {\"property\": \"Status\", \"status\": {\"equals\": \"Done\"}}.",
      %{
        "type" => "object",
        "properties" => %{
          "database" => %{"type" => "string", "description" => "The database id, or the address of its page."},
          "filter" => %{"type" => "object", "description" => "A Notion filter object (optional)."},
          "max" => %{"type" => "integer", "description" => "How many rows to return (1 to 50, default 10)."}
        },
        "required" => ["database"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"database" => database} = args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(50) |> max(1), else: 10
    body = %{"page_size" => max} |> then(&if(is_map(args["filter"]), do: Map.put(&1, "filter", args["filter"]), else: &1))

    with {:ok, id} <- Client.id(database),
         {:ok, settings} <- Client.settings(),
         {:ok, found} <- Client.post(settings, "/v1/databases/#{id}/query", body) do
      case found["results"] do
        [_ | _] = rows -> {:ok, rows |> Enum.map_join("\n\n", &row/1) |> Client.external()}
        _ -> {:ok, "The database has no rows that match."}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "notion_query_database needs a `database` (its id or address)."}

  defp row(page), do: Enum.join(["#{page["id"]}" | Client.properties(page)], "\n  ")
end

defmodule Pepe.Plugins.NotionCreatePage do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Notion.Client

  @impl true
  def name, do: "notion_create_page"

  @impl true
  def spec do
    function(
      "notion_create_page",
      "Create a Notion page with a title and some text, under a page or as a row of a database (both must be shared " <>
        "with the integration). Gives back the new page's link.",
      %{
        "type" => "object",
        "properties" => %{
          "parent" => %{"type" => "string", "description" => "The id (or address) of the page or database to create it in."},
          "parent_type" => %{
            "type" => "string",
            "enum" => ["page", "database"],
            "description" => "Is the parent a page or a database (default page)."
          },
          "title" => %{"type" => "string", "description" => "The page's title."},
          "content" => %{"type" => "string", "description" => "The text. Blank lines split paragraphs."}
        },
        "required" => ["parent", "title"]
      }
    )
  end

  @impl true
  def run(%{"parent" => parent, "title" => title} = args, _ctx) when is_binary(title) and title != "" do
    with :ok <- Client.writable?(),
         {:ok, id} <- Client.id(parent),
         {:ok, settings} <- Client.settings(),
         {:ok, parent_ref, title_property} <- parent_and_title_property(settings, id, args["parent_type"]),
         {:ok, page} <- Client.post(settings, "/v1/pages", payload(parent_ref, title_property, title, args["content"])) do
      {:ok, "Created #{inspect(title)}: #{page["url"]}"}
    end
  end

  def run(_args, _ctx), do: {:error, "notion_create_page needs a `parent` and a `title`."}

  # A page's title property is always `title`; a database names it (often "Name"), so it is read.
  defp parent_and_title_property(_settings, id, type) when type in [nil, "page"], do: {:ok, %{"page_id" => id}, "title"}

  defp parent_and_title_property(settings, id, "database") do
    with {:ok, database} <- Client.get(settings, "/v1/databases/#{id}") do
      case Enum.find(database["properties"] || %{}, fn {_name, p} -> p["type"] == "title" end) do
        {name, _} -> {:ok, %{"database_id" => id}, name}
        nil -> {:error, "That database has no title property."}
      end
    end
  end

  defp parent_and_title_property(_settings, _id, other), do: {:error, "parent_type must be page or database, not #{inspect(other)}."}

  defp payload(parent, title_property, title, content) do
    base = %{
      "parent" => parent,
      "properties" => %{title_property => %{"title" => [%{"type" => "text", "text" => %{"content" => title}}]}}
    }

    case Client.paragraphs(content) do
      [] -> base
      blocks -> Map.put(base, "children", blocks)
    end
  end
end

defmodule Pepe.Plugins.NotionAppend do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Notion.Client

  @impl true
  def name, do: "notion_append"

  @impl true
  def spec do
    function("notion_append", "Add text at the end of a Notion page (it must be shared with the integration).", %{
      "type" => "object",
      "properties" => %{
        "page" => %{"type" => "string", "description" => "The page id, or the address of the page."},
        "text" => %{"type" => "string", "description" => "The text to add. Blank lines split paragraphs."}
      },
      "required" => ["page", "text"]
    })
  end

  @impl true
  def run(%{"page" => page, "text" => text}, _ctx) when is_binary(text) and text != "" do
    with :ok <- Client.writable?(),
         {:ok, id} <- Client.id(page),
         {:ok, settings} <- Client.settings(),
         {:ok, _} <- Client.patch(settings, "/v1/blocks/#{id}/children", %{"children" => Client.paragraphs(text)}) do
      {:ok, "Added the text to the page #{id}."}
    end
  end

  def run(_args, _ctx), do: {:error, "notion_append needs a `page` and some `text`."}
end
