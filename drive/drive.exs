# Google Drive tools for Pepe, as a drop-in plugin. Read only.
#
# Two tools: search files and list a folder, and read a file as text (a Google Doc, Sheet or
# Slides deck is exported to text; a text file is read as it is). Each is an ordinary Pepe tool, so
# an agent holds exactly the ones it is given.
#
# Auth is a Google service account: a robot account with its own e-mail address that sees only the
# files and folders somebody shared with it, so that is also what limits it. There is no consent
# screen and no token to renew by hand. Settings come from the plugin's Configure dialog, falling
# back to environment variables:
#
#   * service_account / GOOGLE_SERVICE_ACCOUNT   the key file's contents (JSON), or the path to the
#                                                file on the machine Pepe runs on
#
# DRIVE_API_URL overrides the address (for a proxy or a test); it is not a normal setting.

defmodule Pepe.Plugins.Drive.Client do
  @moduledoc """
  The service account's sign-in, the HTTP calls, and the conversions the two tools share.
  """

  @scope "https://www.googleapis.com/auth/drive.readonly"
  @id_re ~r/\A[A-Za-z0-9_-]{10,}\z/

  # ---- settings ------------------------------------------------------------------------

  @doc "The service account key (a map), or `{:error, message}` naming what is wrong."
  def account do
    case setting("service_account", "GOOGLE_SERVICE_ACCOUNT") do
      nil ->
        {:error, "Drive is not configured. Set the service account key under Plugins -> Configure (or the GOOGLE_SERVICE_ACCOUNT env var)."}

      value ->
        value |> key_json() |> parse_key()
    end
  end

  defp key_json(value) do
    value = String.trim(value)

    if String.starts_with?(value, "{") do
      {:ok, value}
    else
      case File.read(value) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Could not read the service account key file #{inspect(value)}: #{:file.format_error(reason)}."}
      end
    end
  end

  defp parse_key({:error, _} = error), do: error

  defp parse_key({:ok, json}) do
    case Jason.decode(json) do
      {:ok, %{"client_email" => email, "private_key" => pem} = key} when is_binary(email) and is_binary(pem) ->
        {:ok, %{email: email, pem: pem, token_uri: key["token_uri"] || "https://oauth2.googleapis.com/token"}}

      _ ->
        {:error, "The service account key is not valid. It should be the JSON file Google gives you (with client_email and private_key)."}
    end
  end

  defp api_url, do: (setting("api_url", "DRIVE_API_URL") || "https://www.googleapis.com") |> String.trim() |> String.trim_trailing("/")

  defp setting(key, env_key), do: Pepe.Plugins.config("drive", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # ---- ids -------------------------------------------------------------------------------

  @doc "A file or folder id, from the id itself or from the address of its page in Drive."
  def id(value) do
    raw = value |> to_string() |> String.trim()

    candidate =
      case Regex.run(~r{/(?:d|folders)/([A-Za-z0-9_-]+)}, raw) || Regex.run(~r{[?&]id=([A-Za-z0-9_-]+)}, raw) do
        [_, found] -> found
        nil -> raw
      end

    if Regex.match?(@id_re, candidate),
      do: {:ok, candidate},
      else: {:error, "#{inspect(value)} is not a Drive file or folder id (or the address of one)."}
  end

  def blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  def blank(_value), do: nil

  # ---- signing in --------------------------------------------------------------------------

  @doc "A bearer token for the service account, cached until shortly before it expires."
  def token(account) do
    key = {__MODULE__, :token, account.email}

    case :persistent_term.get(key, nil) do
      {token, expires_at} when is_binary(token) ->
        if System.system_time(:second) < expires_at - 60, do: {:ok, token}, else: sign_in(account, key)

      _ ->
        sign_in(account, key)
    end
  end

  @doc "Drop the cached token (after Google rejected it)."
  def forget_token(account), do: :persistent_term.erase({__MODULE__, :token, account.email})

  defp sign_in(account, key) do
    now = System.system_time(:second)

    claims = %{"iss" => account.email, "scope" => @scope, "aud" => account.token_uri, "iat" => now, "exp" => now + 3600}

    with {:ok, assertion} <- jwt(account.pem, claims) do
      form = %{"grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion" => assertion}

      case Req.post(account.token_uri, form: form, receive_timeout: 20_000, retry: false) do
        {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
          :persistent_term.put(key, {token, now + (body["expires_in"] || 3600)})
          {:ok, token}

        {:ok, %{status: status, body: body}} ->
          {:error,
           "Google did not accept the service account (#{status}#{reason(body)}). Check the key is current and the Drive API is enabled."}

        {:error, reason} ->
          {:error, "Could not reach Google to sign in: #{inspect(reason)}"}
      end
    end
  end

  defp reason(%{"error_description" => text}), do: ": " <> text
  defp reason(%{"error" => text}) when is_binary(text), do: ": " <> text
  defp reason(_body), do: ""

  # RS256: sign `header.claims` with the account's private key.
  defp jwt(pem, claims) do
    header = %{"alg" => "RS256", "typ" => "JWT"}
    input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))

    with {:ok, private_key} <- private_key(pem) do
      {:ok, input <> "." <> b64(:public_key.sign(input, :sha256, private_key))}
    end
  rescue
    _ -> {:error, "The service account's private key could not be read."}
  end

  defp private_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      [] -> {:error, "The service account's private key could not be read."}
    end
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)

  # ---- http ----------------------------------------------------------------------------

  @doc "GET a path under the Drive API as the service account, signing in (and once more after a rejection) as needed."
  def get(account, path, params \\ [], retry? \\ true) do
    with {:ok, token} <- token(account) do
      case Req.get(api_url() <> path, auth: {:bearer, token}, params: params, receive_timeout: 30_000, retry: false) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: 401}} when retry? ->
          forget_token(account)
          get(account, path, params, false)

        {:ok, %{status: status, body: body} = response} ->
          {:error, explain(status, body, response)}

        {:error, reason} ->
          {:error, "Could not reach Google Drive: #{inspect(reason)}"}
      end
    end
  end

  defp explain(401, _body, _response), do: "Google Drive did not accept the service account. Check the key is current."

  defp explain(403, body, response) do
    if rate_limited?(body),
      do: "Google Drive is rate limiting this account#{retry_after(response)}.",
      else: "Google Drive says this account may not do that#{message(body)}"
  end

  defp explain(404, _body, _response),
    do: "Google Drive could not find it. The file or folder has to be shared with the service account's e-mail."

  defp explain(429, _body, response), do: "Google Drive is rate limiting this account#{retry_after(response)}."
  defp explain(status, body, _response), do: "Google Drive answered with an error (#{status})#{message(body)}"

  defp rate_limited?(%{"error" => %{"errors" => errors}}) when is_list(errors),
    do: Enum.any?(errors, &(&1["reason"] in ["rateLimitExceeded", "userRateLimitExceeded"]))

  defp rate_limited?(_body), do: false

  defp retry_after(response) do
    case Req.Response.get_header(response, "retry-after") do
      [seconds | _] -> ". Try again in #{seconds} seconds"
      _ -> ". Try again in a moment"
    end
  end

  defp message(%{"error" => %{"message" => text}}), do: ": " <> text
  defp message(_body), do: "."

  # ---- what comes back -------------------------------------------------------------------

  @doc "A short name for a file's type."
  def kind("application/vnd.google-apps.document"), do: "Google Doc"
  def kind("application/vnd.google-apps.spreadsheet"), do: "Google Sheet"
  def kind("application/vnd.google-apps.presentation"), do: "Google Slides"
  def kind("application/vnd.google-apps.folder"), do: "folder"
  def kind("application/pdf"), do: "PDF"
  def kind(mime), do: to_string(mime)

  @doc "One line for a file."
  def line(file) do
    size = if file["size"], do: ", #{file["size"]} bytes", else: ""

    "#{file["name"]} (#{kind(file["mimeType"])}, edited #{String.slice(to_string(file["modifiedTime"]), 0, 10)}#{size})\n  id: #{file["id"]}#{if file["webViewLink"], do: "  " <> file["webViewLink"], else: ""}"
  end

  @doc "A value as it goes inside quotes in a Drive search."
  def escape_value(text), do: text |> to_string() |> String.replace("\\", "\\\\") |> String.replace("'", "\\'")

  @doc """
  Text that came out of Drive is written by whoever can edit the file, so it reaches the model
  framed as quoted material, never as instructions.
  """
  def external(text) do
    Pepe.Security.ExternalContent.mark_untrusted("drive", Pepe.Security.ExternalContent.sanitize(text))
  end

  @doc "Cut a text to a length, saying so when it was cut."
  def clip(text, max) do
    text = to_string(text)
    if String.length(text) > max, do: String.slice(text, 0, max) <> "\n[... cut, #{String.length(text) - max} more characters]", else: text
  end
end

defmodule Pepe.Plugins.DriveSearch do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Drive.Client

  @types %{
    "doc" => "application/vnd.google-apps.document",
    "sheet" => "application/vnd.google-apps.spreadsheet",
    "slides" => "application/vnd.google-apps.presentation",
    "folder" => "application/vnd.google-apps.folder",
    "pdf" => "application/pdf"
  }

  @impl true
  def name, do: "drive_search"

  @impl true
  def spec do
    function(
      "drive_search",
      "Search the Google Drive files and folders that were shared with the service account, or list one folder. " <>
        "Gives back names, types, ids and links. With no arguments it lists the most recently edited.",
      %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Words to look for in the name or the text of the files (optional)."},
          "folder" => %{"type" => "string", "description" => "A folder id or address, to list or search only inside it (optional)."},
          "type" => %{"type" => "string", "enum" => Map.keys(@types), "description" => "Only this kind of file (optional)."},
          "max" => %{"type" => "integer", "description" => "How many to return (1 to 50, default 15)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true

  # Names and the text of files are written by whoever can edit them.
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(50) |> max(1), else: 15

    with {:ok, account} <- Client.account(),
         {:ok, clauses} <- clauses(args),
         {:ok, body} <-
           Client.get(account, "/drive/v3/files",
             q: Enum.join(clauses, " and "),
             pageSize: max,
             orderBy: "modifiedTime desc",
             fields: "files(id,name,mimeType,modifiedTime,size,webViewLink)",
             supportsAllDrives: true,
             includeItemsFromAllDrives: true
           ) do
      case body["files"] do
        [_ | _] = files -> {:ok, files |> Enum.map_join("\n", &Client.line/1) |> Client.external()}
        _ -> {:ok, "Nothing matches (only what was shared with the service account can be found)."}
      end
    end
  end

  defp clauses(args) do
    with {:ok, folder} <- folder(args["folder"]) do
      query = Client.blank(args["query"])
      type = @types[args["type"]]

      {:ok,
       ["trashed = false"] ++
         if(folder, do: ["'#{folder}' in parents"], else: []) ++
         if(query, do: ["(name contains '#{Client.escape_value(query)}' or fullText contains '#{Client.escape_value(query)}')"], else: []) ++
         if(type, do: ["mimeType = '#{type}'"], else: [])}
    end
  end

  defp folder(nil), do: {:ok, nil}

  defp folder(value) do
    case Client.blank(value) do
      nil -> {:ok, nil}
      _ -> Client.id(value)
    end
  end
end

defmodule Pepe.Plugins.DriveGetFile do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Drive.Client

  # What is worth putting in front of a model, and the biggest plain file worth downloading to find out.
  @max_chars 20_000
  @max_bytes 1_000_000

  @exports %{
    "application/vnd.google-apps.document" => "text/plain",
    "application/vnd.google-apps.presentation" => "text/plain",
    "application/vnd.google-apps.spreadsheet" => "text/csv"
  }

  @text_types ["application/json", "application/xml", "application/x-yaml", "application/javascript"]

  @impl true
  def name, do: "drive_get_file"

  @impl true
  def spec do
    function(
      "drive_get_file",
      "Read a file from Google Drive as text. A Google Doc or Slides deck is read as plain text, a Sheet as CSV (its first " <>
        "sheet), a text file as it is. Takes the file's id or its address. Other kinds (PDF, images) give only their details.",
      %{
        "type" => "object",
        "properties" => %{"file" => %{"type" => "string", "description" => "The file id, or the address of the file."}},
        "required" => ["file"]
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"file" => file}, _ctx) do
    with {:ok, id} <- Client.id(file),
         {:ok, account} <- Client.account(),
         {:ok, meta} <-
           Client.get(account, "/drive/v3/files/#{id}",
             fields: "id,name,mimeType,size,modifiedTime,webViewLink,trashed",
             supportsAllDrives: true
           ),
         {:ok, text} <- content(account, id, meta) do
      {:ok, (Client.line(meta) <> "\n\n" <> text) |> Client.clip(@max_chars + 500) |> Client.external()}
    end
  end

  def run(_args, _ctx), do: {:error, "drive_get_file needs a `file` (its id or address)."}

  defp content(account, id, %{"mimeType" => mime} = meta) do
    cond do
      mime == "application/vnd.google-apps.folder" ->
        {:ok, "(a folder: use drive_search with this folder to list what is in it)"}

      Map.has_key?(@exports, mime) ->
        account |> Client.get("/drive/v3/files/#{id}/export", mimeType: @exports[mime]) |> as_text()

      text_file?(mime) and size(meta) <= @max_bytes ->
        account |> Client.get("/drive/v3/files/#{id}", alt: "media", supportsAllDrives: true) |> as_text()

      text_file?(mime) ->
        {:ok, "(a text file of #{size(meta)} bytes, too large to read here)"}

      true ->
        {:ok, "(not a text file: #{Client.kind(mime)}#{if size(meta) > 0, do: ", #{size(meta)} bytes"}; only its details are shown)"}
    end
  end

  defp text_file?(mime), do: String.starts_with?(mime, "text/") or mime in @text_types

  defp size(%{"size" => size}) when is_binary(size), do: String.to_integer(size)
  defp size(_meta), do: 0

  defp as_text({:ok, body}) when is_binary(body),
    do: if(String.valid?(body), do: {:ok, Client.clip(body, @max_chars)}, else: {:ok, "(the file is not text)"})

  defp as_text({:ok, body}), do: {:ok, Client.clip(Jason.encode!(body, pretty: true), @max_chars)}
  defp as_text({:error, _} = error), do: error
end
