defmodule Pepe.Plugins.DriveTest do
  @moduledoc """
  The Drive plugin against a fake Google: the service account's sign-in (the signature is
  checked for real, with the account's public key), what the tools ask for, how they read the
  answers, and what they refuse to do. Nothing here talks to the real service.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.Drive.Client
  alias Pepe.Plugins.DriveGetFile
  alias Pepe.Plugins.DriveSearch

  @doc_id "1AbCdEfGhIjKlMnOpQrStUvWxYz"
  @sheet_id "2AbCdEfGhIjKlMnOpQrStUvWxYz"
  @txt_id "3AbCdEfGhIjKlMnOpQrStUvWxYz"
  @pdf_id "4AbCdEfGhIjKlMnOpQrStUvWxYz"
  @big_id "5AbCdEfGhIjKlMnOpQrStUvWxYz"
  @folder_id "6AbCdEfGhIjKlMnOpQrStUvWxYz"
  @ghost_id "7AbCdEfGhIjKlMnOpQrStUvWxYz"
  @expiring_id "8AbCdEfGhIjKlMnOpQrStUvWxYz"

  defmodule FakeGoogle do
    @moduledoc false
    import Plug.Conn

    @doc_id "1AbCdEfGhIjKlMnOpQrStUvWxYz"
    @sheet_id "2AbCdEfGhIjKlMnOpQrStUvWxYz"
    @txt_id "3AbCdEfGhIjKlMnOpQrStUvWxYz"
    @pdf_id "4AbCdEfGhIjKlMnOpQrStUvWxYz"
    @big_id "5AbCdEfGhIjKlMnOpQrStUvWxYz"
    @folder_id "6AbCdEfGhIjKlMnOpQrStUvWxYz"
    @expiring_id "8AbCdEfGhIjKlMnOpQrStUvWxYz"

    def init(test), do: test

    def call(conn, test) do
      conn = fetch_query_params(conn)
      {:ok, raw, conn} = read_body(conn)
      form = if raw == "", do: %{}, else: URI.decode_query(raw)
      headers = Map.new(conn.req_headers)
      send(test, {:request, conn.method, conn.request_path, conn.query_params, form, headers})

      case {conn.method, conn.request_path} do
        {"POST", "/token"} ->
          token_for(conn, form, test)

        {"GET", "/drive/v3/files"} ->
          json(conn, 200, %{
            "files" => [file(@doc_id, "Plan", "application/vnd.google-apps.document"), file(@pdf_id, "Contract", "application/pdf")]
          })

        {"GET", "/drive/v3/files/" <> @doc_id} ->
          json(conn, 200, file(@doc_id, "Plan", "application/vnd.google-apps.document"))

        {"GET", "/drive/v3/files/" <> @doc_id <> "/export"} ->
          text(conn, "Plan\n\nShip it soon.")

        {"GET", "/drive/v3/files/" <> @sheet_id} ->
          json(conn, 200, file(@sheet_id, "Budget", "application/vnd.google-apps.spreadsheet"))

        {"GET", "/drive/v3/files/" <> @sheet_id <> "/export"} ->
          text(conn, "item,cost\nrent,1000\n")

        {"GET", "/drive/v3/files/" <> @txt_id} ->
          if conn.query_params["alt"] == "media",
            do: text(conn, "plain notes"),
            else: json(conn, 200, Map.put(file(@txt_id, "notes.txt", "text/plain"), "size", "11"))

        {"GET", "/drive/v3/files/" <> @pdf_id} ->
          json(conn, 200, Map.put(file(@pdf_id, "Contract", "application/pdf"), "size", "52000"))

        {"GET", "/drive/v3/files/" <> @big_id} ->
          json(conn, 200, Map.put(file(@big_id, "huge.txt", "text/plain"), "size", "9000000"))

        {"GET", "/drive/v3/files/" <> @folder_id} ->
          json(conn, 200, file(@folder_id, "Docs", "application/vnd.google-apps.folder"))

        {"GET", "/drive/v3/files/" <> @expiring_id} ->
          if headers["authorization"] == "Bearer token-1",
            do: json(conn, 401, %{"error" => %{"message" => "Invalid Credentials"}}),
            else: json(conn, 200, file(@expiring_id, "Late", "application/vnd.google-apps.folder"))

        {"GET", "/drive/v3/files/7AbCdEfGhIjKlMnOpQrStUvWxYz"} ->
          json(conn, 404, %{"error" => %{"message" => "File not found"}})

        {"GET", "/drive/v3/files/9" <> _} ->
          conn |> put_resp_header("retry-after", "12") |> json(429, %{"error" => %{"message" => "slow down"}})

        _ ->
          json(conn, 404, %{"error" => %{"message" => "File not found"}})
      end
    end

    # Checks the sign-in the way Google would: RS256, over header.claims, with the account's public key.
    defp token_for(conn, %{"assertion" => jwt, "grant_type" => grant}, test) do
      [header, claims, signature] = String.split(jwt, ".")
      public = Application.fetch_env!(:pepe_plugins, :test_public_key)
      valid? = :public_key.verify(header <> "." <> claims, :sha256, Base.url_decode64!(signature, padding: false), public)

      send(
        test,
        {:sign_in, grant, Jason.decode!(Base.url_decode64!(claims, padding: false)),
         Jason.decode!(Base.url_decode64!(header, padding: false)), valid?}
      )

      if valid?,
        do: json(conn, 200, %{"access_token" => "token-#{System.unique_integer([:positive])}", "expires_in" => 3600}),
        else: json(conn, 400, %{"error" => "invalid_grant", "error_description" => "Invalid JWT Signature."})
    end

    defp json(conn, status, data), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
    defp text(conn, body), do: conn |> put_resp_content_type("text/plain") |> send_resp(200, body)

    defp file(id, name, mime) do
      %{
        "id" => id,
        "name" => name,
        "mimeType" => mime,
        "modifiedTime" => "2026-10-02T10:00:00Z",
        "webViewLink" => "https://drive.google.com/file/d/#{id}/view"
      }
    end
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: {FakeGoogle, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)
    base = "http://127.0.0.1:#{port}"

    # A real RSA key, written the way Google writes one (PKCS#8), so the signing is exercised for real.
    private = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = private
    Application.put_env(:pepe_plugins, :test_public_key, {:RSAPublicKey, modulus, exponent})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:PrivateKeyInfo, private)])

    key =
      Jason.encode!(%{
        "type" => "service_account",
        "client_email" => "pepe@proj.iam.gserviceaccount.com",
        "private_key" => pem,
        "token_uri" => base <> "/token"
      })

    Application.put_env(:pepe_plugins, :plugin_config, %{"drive" => %{"service_account" => key, "api_url" => base}})
    :persistent_term.erase({Client, :token, "pepe@proj.iam.gserviceaccount.com"})

    on_exit(fn ->
      Application.delete_env(:pepe_plugins, :plugin_config)
      Application.delete_env(:pepe_plugins, :test_public_key)
      :persistent_term.erase({Client, :token, "pepe@proj.iam.gserviceaccount.com"})
    end)

    %{key: key, base: base}
  end

  describe "signing in" do
    test "a signed JWT is exchanged for a token that Google verifies, and the token rides on the call" do
      assert {:ok, _} = DriveSearch.run(%{}, %{})

      assert_received {:sign_in, "urn:ietf:params:oauth:grant-type:jwt-bearer", claims, header, true}
      assert header == %{"alg" => "RS256", "typ" => "JWT"}
      assert claims["iss"] == "pepe@proj.iam.gserviceaccount.com"
      assert claims["scope"] == "https://www.googleapis.com/auth/drive.readonly"
      assert claims["exp"] - claims["iat"] == 3600
      assert_received {:request, "GET", "/drive/v3/files", _, _, %{"authorization" => "Bearer token-" <> _}}
    end

    test "the token is reused for the next call, not asked for again" do
      assert {:ok, _} = DriveSearch.run(%{}, %{})
      assert {:ok, _} = DriveSearch.run(%{"query" => "plan"}, %{})
      assert_received {:sign_in, _, _, _, _}
      refute_received {:sign_in, _, _, _, _}
    end

    test "a token Google stopped accepting is replaced once, and the call goes through" do
      assert {:ok, _} = DriveSearch.run(%{}, %{})
      :persistent_term.put({Client, :token, "pepe@proj.iam.gserviceaccount.com"}, {"token-1", System.system_time(:second) + 3000})

      assert {:ok, out} = DriveGetFile.run(%{"file" => @expiring_id}, %{})
      assert out =~ "Late"
    end

    test "the key can be a path to the file instead of its contents", %{key: key} do
      path = Path.join(System.tmp_dir!(), "drive_key_#{System.unique_integer([:positive])}.json")
      File.write!(path, key)
      on_exit(fn -> File.rm(path) end)

      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["drive", "service_account"], path))
      assert {:ok, _} = DriveSearch.run(%{}, %{})
    end

    test "a key that is not a service account key says so, before any request" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["drive", "service_account"], ~s({"hello": "world"})))
      assert {:error, msg} = DriveSearch.run(%{}, %{})
      assert msg =~ "not valid"

      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["drive", "service_account"], "/no/such/file.json"))
      assert {:error, missing} = DriveSearch.run(%{}, %{})

      assert missing =~ "Could not read the service account key file"
      refute_received {:request, _, _, _, _, _}
    end

    test "no settings at all says what to fill in" do
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = DriveSearch.run(%{}, %{})
      assert msg =~ "Drive is not configured"
    end
  end

  describe "search" do
    test "lists the most recent files, not trashed, across shared drives" do
      assert {:ok, out} = DriveSearch.run(%{"max" => 5}, %{})

      assert_received {:request, "GET", "/drive/v3/files", query, _, _}
      assert query["q"] == "trashed = false"
      assert query["pageSize"] == "5"
      assert query["orderBy"] == "modifiedTime desc"
      assert query["supportsAllDrives"] == "true"

      assert out =~ "Plan (Google Doc, edited 2026-10-02)"
      assert out =~ "id: #{@doc_id}"
      assert out =~ "Contract (PDF"
    end

    test "words, a folder and a type are put together, with quotes made safe" do
      assert {:ok, _} =
               DriveSearch.run(
                 %{
                   "query" => "O'Brien \\ plan",
                   "folder" => "https://drive.google.com/drive/folders/#{@folder_id}?usp=sharing",
                   "type" => "sheet"
                 },
                 %{}
               )

      assert_received {:request, "GET", "/drive/v3/files", %{"q" => q}, _, _}
      assert q =~ "'#{@folder_id}' in parents"
      assert q =~ "name contains 'O\\'Brien \\\\ plan'"
      assert q =~ "fullText contains 'O\\'Brien \\\\ plan'"
      assert q =~ "mimeType = 'application/vnd.google-apps.spreadsheet'"
    end

    test "a folder that is not an id is refused before any request" do
      assert {:error, msg} = DriveSearch.run(%{"folder" => "root' or '1'='1"}, %{})
      assert msg =~ "not a Drive file or folder id"
      refute_received {:request, _, _, _, _, _}
    end
  end

  describe "reading" do
    test "a Google Doc is exported as plain text, a Sheet as CSV" do
      assert {:ok, doc} = DriveGetFile.run(%{"file" => "https://docs.google.com/document/d/#{@doc_id}/edit"}, %{})
      assert doc =~ "Plan (Google Doc"
      assert doc =~ "Ship it soon."
      assert_received {:request, "GET", "/drive/v3/files/" <> _, %{"mimeType" => "text/plain"}, _, _}

      assert {:ok, sheet} = DriveGetFile.run(%{"file" => @sheet_id}, %{})
      assert sheet =~ "item,cost\nrent,1000"
    end

    test "a text file is read as it is, within a size limit" do
      assert {:ok, out} = DriveGetFile.run(%{"file" => @txt_id}, %{})
      assert out =~ "plain notes"
      assert_received {:request, "GET", _, %{"alt" => "media"}, _, _}

      assert {:ok, big} = DriveGetFile.run(%{"file" => @big_id}, %{})
      assert big =~ "too large to read here"
    end

    test "a PDF, and a folder, give only their details" do
      assert {:ok, pdf} = DriveGetFile.run(%{"file" => @pdf_id}, %{})
      assert pdf =~ "not a text file: PDF, 52000 bytes"
      assert {:ok, folder} = DriveGetFile.run(%{"file" => @folder_id}, %{})
      assert folder =~ "a folder: use drive_search"
    end

    test "what comes out of Drive is framed as external content, never as instructions" do
      {:ok, search} = DriveSearch.run(%{}, %{})
      {:ok, file} = DriveGetFile.run(%{"file" => @doc_id}, %{})

      for out <- [search, file], do: assert(out =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: drive")
      assert DriveSearch.outside_content?() and DriveGetFile.outside_content?()
    end

    test "something that is not an id never reaches the network" do
      assert {:error, _} = DriveGetFile.run(%{"file" => "../../about"}, %{})
      refute_received {:request, _, _, _, _, _}
    end
  end

  describe "when Google says no" do
    test "a file that was not shared with the account says how to share it" do
      assert {:error, msg} = DriveGetFile.run(%{"file" => @ghost_id}, %{})
      assert msg =~ "has to be shared with the service account's e-mail"
    end

    test "a rate limit says how long to wait, at once" do
      {micros, result} = :timer.tc(fn -> DriveGetFile.run(%{"file" => "9AbCdEfGhIjKlMnOpQrStUvWxYz"}, %{}) end)
      assert {:error, msg} = result
      assert msg =~ "rate limiting"
      assert msg =~ "12 seconds"
      assert micros < 2_000_000
    end

    test "a sign-in Google refuses is told with its reason" do
      # Google checks the signature against a different key than the one the account signed with.
      {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = :public_key.generate_key({:rsa, 2048, 65_537})
      Application.put_env(:pepe_plugins, :test_public_key, {:RSAPublicKey, modulus, exponent})
      assert {:error, msg} = DriveSearch.run(%{}, %{})
      assert msg =~ "did not accept the service account"
      assert msg =~ "Invalid JWT Signature"
    end
  end
end
