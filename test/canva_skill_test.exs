defmodule CanvaSkillTest do
  @moduledoc """
  The canva-template-image skill's script against a fake Canva Connect API: the PKCE sign-in, token
  rotation, listing templates, autofill, export, and what it refuses or hides. Nothing here talks
  to the real service.
  """
  use ExUnit.Case, async: false

  @script Path.expand("../skills/canva-template-image/scripts/canva.sh", __DIR__)
  @client_id "OC-FAKE-ID"
  @client_secret "cnvcaFAKEsecret123"
  @redirect "http://127.0.0.1:3000/callback"

  @tools_missing Enum.reject(["curl", "jq"], &System.find_executable/1)
  if @tools_missing != [] do
    @moduletag skip: "needs #{Enum.join(@tools_missing, " and ")} on the PATH"
  end

  defmodule FakeCanva do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, {test, agent}) do
      {:ok, raw, conn} = read_body(conn)
      conn = fetch_query_params(conn)
      send(test, {:request, conn.method, conn.request_path, raw, conn.req_headers, conn.query_params})
      route(conn, conn.method, conn.request_path, raw, agent)
    end

    defp route(conn, "POST", "/oauth/token", raw, agent) do
      form = URI.decode_query(raw)
      basic = "Basic " <> Base.encode64("OC-FAKE-ID:cnvcaFAKEsecret123")

      cond do
        get_req_header(conn, "authorization") != [basic] ->
          json(conn, 401, %{"code" => "invalid_client", "message" => "bad client"})

        form["grant_type"] == "authorization_code" ->
          challenge = Agent.get(agent, & &1.challenge)
          verifier_hash = :crypto.hash(:sha256, form["code_verifier"] || "") |> Base.url_encode64(padding: false)

          if form["code"] == "the-code" and verifier_hash == challenge do
            issue(conn, agent, 1)
          else
            json(conn, 400, %{"error" => "invalid_grant", "error_description" => "bad code or verifier"})
          end

        form["grant_type"] == "refresh_token" ->
          valid = Agent.get(agent, & &1.refresh)

          if form["refresh_token"] == valid do
            issue(conn, agent, Agent.get_and_update(agent, &{&1.n + 1, %{&1 | n: &1.n + 1}}))
          else
            json(conn, 400, %{"error" => "invalid_grant", "error_description" => "refresh token already used"})
          end
      end
    end

    # the pre-signed download link needs no token
    defp route(conn, "GET", "/files/page1.png", _raw, _agent), do: send_resp(conn, 200, "PNGDATA")

    defp route(conn, method, path, raw, agent) do
      expected = "Bearer " <> Agent.get(agent, fn state -> state.access end)

      if expected in get_req_header(conn, "authorization") do
        api(conn, method, path, raw, agent)
      else
        json(conn, 401, %{"code" => "unauthorized", "message" => "bad token"})
      end
    end

    defp api(conn, "GET", "/brand-templates", _raw, _agent) do
      json(conn, 200, %{"items" => [%{"id" => "DAT1", "title" => "Post\nquadrado"}, %{"id" => "DAT2", "title" => "Story"}]})
    end

    defp api(conn, "GET", "/brand-templates/DAT1/dataset", _raw, _agent) do
      json(conn, 200, %{"dataset" => %{"title" => %{"type" => "text"}, "photo" => %{"type" => "image"}}})
    end

    defp api(conn, "POST", "/url-asset-uploads", _raw, _agent) do
      json(conn, 200, %{"job" => %{"id" => "up1", "status" => "in_progress"}})
    end

    defp api(conn, "GET", "/url-asset-uploads/up1", _raw, _agent) do
      json(conn, 200, %{"job" => %{"id" => "up1", "status" => "success", "asset" => %{"id" => "Masset1"}}})
    end

    defp api(conn, "POST", "/asset-uploads", _raw, _agent) do
      json(conn, 200, %{"job" => %{"id" => "up2", "status" => "in_progress"}})
    end

    defp api(conn, "GET", "/asset-uploads/up2", _raw, _agent) do
      json(conn, 200, %{"job" => %{"id" => "up2", "status" => "success", "asset" => %{"id" => "Mfile1"}}})
    end

    defp api(conn, "POST", "/autofills", raw, _agent) do
      status = if raw =~ "FAILME", do: "fail1", else: "af1"
      json(conn, 200, %{"job" => %{"id" => status, "status" => "in_progress"}})
    end

    defp api(conn, "GET", "/autofills/af1", _raw, agent) do
      # first poll still running, then done
      if Agent.get_and_update(agent, &{&1.polls, %{&1 | polls: &1.polls + 1}}) == 0 do
        json(conn, 200, %{"job" => %{"id" => "af1", "status" => "in_progress"}})
      else
        design = %{"id" => "DAdesign1", "url" => "https://www.canva.com/design/DAdesign1/edit"}
        json(conn, 200, %{"job" => %{"id" => "af1", "status" => "success", "result" => %{"type" => "create_design", "design" => design}}})
      end
    end

    defp api(conn, "GET", "/autofills/fail1", _raw, _agent) do
      error = %{"code" => "trial_quota_exceeded", "message" => "The autofill quota is used up"}
      json(conn, 200, %{"job" => %{"id" => "fail1", "status" => "failed", "error" => error}})
    end

    defp api(conn, "POST", "/exports", _raw, _agent) do
      json(conn, 200, %{"job" => %{"id" => "ex1", "status" => "in_progress"}})
    end

    defp api(conn, "GET", "/exports/ex1", _raw, _agent) do
      url = "http://127.0.0.1:#{conn.port}/files/page1.png"
      json(conn, 200, %{"job" => %{"id" => "ex1", "status" => "success", "urls" => [url, "http://127.0.0.1/ignored"]}})
    end

    defp api(conn, method, path, _raw, _agent), do: json(conn, 404, %{"code" => "not_found", "message" => "no #{method} #{path}"})

    defp issue(conn, agent, n) do
      refresh = "RT-#{n}"
      Agent.update(agent, &%{&1 | access: "AT-#{n}", refresh: refresh})
      json(conn, 200, %{"access_token" => "AT-#{n}", "refresh_token" => refresh, "token_type" => "Bearer", "expires_in" => 14_400})
    end

    defp json(conn, status, body) do
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
    end
  end

  setup do
    {:ok, agent} = Agent.start_link(fn -> %{challenge: nil, access: "", refresh: "", n: 1, polls: 0} end)
    {:ok, server} = Bandit.start_link(plug: {FakeCanva, {self(), agent}}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)
    state = Path.join(System.tmp_dir!(), "canva-skill-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(state) end)
    {:ok, agent: agent, state: state, api: "http://127.0.0.1:#{port}"}
  end

  defp canva(ctx, args, extra_env \\ []) do
    env =
      [
        {"CANVA_API_URL", ctx.api},
        {"CANVA_STATE_DIR", ctx.state},
        {"CANVA_CLIENT_ID", @client_id},
        {"CANVA_CLIENT_SECRET", @client_secret},
        {"CANVA_REDIRECT_URI", @redirect},
        {"CANVA_POLL_SLEEP", "0"}
      ] ++ extra_env

    {out, code} = System.cmd("bash", [@script | args], env: env, stderr_to_stdout: true, cd: ctx.state |> tap(&File.mkdir_p!/1))
    send(self(), {:output, out})
    {out, code}
  end

  # Runs the real sign-in: auth-url, then auth-code against the fake.
  defp authorize(ctx) do
    {url, 0} = canva(ctx, ["auth-url"])
    %{"code_challenge" => challenge, "state" => state} = url |> String.trim() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    Agent.update(ctx.agent, &%{&1 | challenge: challenge})
    {_, 0} = canva(ctx, ["auth-code", "the-code", state])
  end

  defp tokens(ctx), do: Path.join(ctx.state, "tokens.json") |> File.read!() |> Jason.decode!()

  defp requests(acc \\ []) do
    receive do
      {:request, method, path, body, headers, query} -> requests([{method, path, body, headers, query} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp assert_no_secrets(outputs) do
    for out <- outputs, secret <- [@client_secret, "AT-", "RT-"] do
      refute out =~ secret, "output leaked #{secret}: #{out}"
    end
  end

  test "auth-url carries the PKCE challenge, the scopes and no secret", ctx do
    {out, 0} = canva(ctx, ["auth-url"])
    uri = out |> String.trim() |> URI.parse()
    q = URI.decode_query(uri.query)

    assert "#{uri.scheme}://#{uri.host}#{uri.path}" == "https://www.canva.com/api/oauth/authorize"
    assert q["code_challenge_method"] == "S256"
    assert q["code_challenge"] =~ ~r/^[A-Za-z0-9_-]{43}$/
    assert q["client_id"] == @client_id
    assert q["redirect_uri"] == @redirect
    assert q["response_type"] == "code"

    assert Enum.sort(String.split(q["scope"])) ==
             Enum.sort(
               ~w(design:content:read design:content:write brandtemplate:meta:read brandtemplate:content:read asset:read asset:write)
             )

    refute out =~ @client_secret

    verifier = File.read!(Path.join(ctx.state, "pkce_verifier"))
    assert Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false) == q["code_challenge"]
    assert File.read!(Path.join(ctx.state, "pkce_state")) == q["state"]
  end

  test "auth-code stores the tokens with mode 600 and never prints them", ctx do
    {url, 0} = canva(ctx, ["auth-url"])
    q = url |> String.trim() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    Agent.update(ctx.agent, &%{&1 | challenge: q["code_challenge"]})

    {out, 0} = canva(ctx, ["auth-code", "the-code", q["state"]])
    assert_no_secrets([out])

    path = Path.join(ctx.state, "tokens.json")
    assert %{"access_token" => "AT-1", "refresh_token" => "RT-1", "expires_at" => exp} = tokens(ctx)
    assert exp > System.os_time(:second) + 14_000
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    refute File.exists?(Path.join(ctx.state, "pkce_verifier"))

    assert {"authorized" <> _, 0} = canva(ctx, ["status"])
  end

  test "auth-code with a wrong state or a missing sign-in is refused", ctx do
    assert {out, 1} = canva(ctx, ["auth-code", "the-code"])
    assert out =~ "run auth-url first"

    {_, 0} = canva(ctx, ["auth-url"])
    assert {out, 1} = canva(ctx, ["auth-code", "the-code", "not-the-state"])
    assert out =~ "state does not match"
    assert requests() == []
  end

  test "status says so when not authorized", ctx do
    assert {out, 1} = canva(ctx, ["status"])
    assert out =~ "not authorized"
  end

  test "an expiring access token is refreshed and the rotated refresh token is saved", ctx do
    authorize(ctx)
    requests()

    # make the stored token look about to expire
    path = Path.join(ctx.state, "tokens.json")
    File.write!(path, tokens(ctx) |> Map.put("expires_at", System.os_time(:second) + 10) |> Jason.encode!())

    {out, 0} = canva(ctx, ["templates"])
    assert out =~ "DAT1"
    assert %{"access_token" => "AT-2", "refresh_token" => "RT-2"} = tokens(ctx)
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600

    [{"POST", "/oauth/token", body, _, _}, {"GET", "/brand-templates", _, headers, _}] = requests()
    assert URI.decode_query(body) == %{"grant_type" => "refresh_token", "refresh_token" => "RT-1"}
    assert {"authorization", "Bearer AT-2"} in headers

    # the old refresh token is dead on the server, so a second refresh must use the new one
    File.write!(path, tokens(ctx) |> Map.put("expires_at", System.os_time(:second) + 10) |> Jason.encode!())
    assert {_, 0} = canva(ctx, ["templates"])
    assert %{"refresh_token" => "RT-3"} = tokens(ctx)
  end

  test "templates and fields are parsed into plain lines", ctx do
    authorize(ctx)
    {out, 0} = canva(ctx, ["templates", "post"])
    assert out == "DAT1\tPost quadrado\nDAT2\tStory\n"

    {fields, 0} = canva(ctx, ["fields", "DAT1"])
    assert fields |> String.split("\n", trim: true) |> Enum.sort() == ["photo\timage", "title\ttext"]

    reqs = requests()

    assert Enum.any?(reqs, fn
             {"GET", "/brand-templates", _, _, q} -> q["query"] == "post" and q["dataset"] == "non_empty"
             _ -> false
           end)
  end

  test "upload from an https URL and from a file prints the asset id", ctx do
    authorize(ctx)
    requests()

    assert {"Masset1\n", 0} = canva(ctx, ["upload", "https://example.com/bg/photo.jpg", "Background"])
    [{"POST", "/url-asset-uploads", body, _, _} | _] = requests()
    assert Jason.decode!(body) == %{"name" => "Background", "url" => "https://example.com/bg/photo.jpg"}

    file = Path.join(ctx.state, "bg.jpg")
    File.write!(file, "JPEGBYTES")
    assert {"Mfile1\n", 0} = canva(ctx, ["upload", file])
    {"POST", "/asset-uploads", body, headers, _} = Enum.find(requests(), &match?({"POST", "/asset-uploads", _, _, _}, &1))
    assert body == "JPEGBYTES"
    {_, meta} = List.keyfind(headers, "asset-upload-metadata", 0)
    assert Jason.decode!(meta) == %{"name_base64" => Base.encode64("bg.jpg")}
  end

  test "fill posts the text and image fields, polls, and prints the design", ctx do
    authorize(ctx)
    requests()

    {out, 0} = canva(ctx, ["fill", "DAT1", "--title", "My post", "--text", "title=Olá = mundo", "--image", "photo=Masset1"])
    assert out == "design_id: DAdesign1\nedit_url: https://www.canva.com/design/DAdesign1/edit\n"

    reqs = requests()
    {"POST", "/autofills", body, _, _} = Enum.find(reqs, &match?({"POST", "/autofills", _, _, _}, &1))

    assert Jason.decode!(body) == %{
             "type" => "create_from_brand_template",
             "brand_template_id" => "DAT1",
             "title" => "My post",
             "data" => %{"title" => %{"type" => "text", "text" => "Olá = mundo"}, "photo" => %{"type" => "image", "asset_id" => "Masset1"}}
           }

    assert Enum.count(reqs, &match?({"GET", "/autofills/af1", _, _, _}, &1)) == 2
  end

  test "fill refuses a field the template does not have, before creating anything", ctx do
    authorize(ctx)
    requests()
    assert {out, 1} = canva(ctx, ["fill", "DAT1", "--text", "headline=Hi"])
    assert out =~ ~s(no text field "headline")
    assert out =~ "photo (image), title (text)"
    refute Enum.any?(requests(), &match?({"POST", "/autofills", _, _, _}, &1))
  end

  test "export downloads the first file", ctx do
    authorize(ctx)
    out_path = Path.join(ctx.state, "post.png")
    {out, 0} = canva(ctx, ["export", "DAdesign1", "--out", out_path])
    assert out == out_path <> "\n"
    assert File.read!(out_path) == "PNGDATA"

    reqs = requests()
    {"POST", "/exports", body, _, _} = Enum.find(reqs, &match?({"POST", "/exports", _, _, _}, &1))
    assert Jason.decode!(body) == %{"design_id" => "DAdesign1", "format" => %{"type" => "png"}}
    # the pre-signed download carries no token
    {_, _, _, headers, _} = Enum.find(reqs, &match?({"GET", "/files/page1.png", _, _, _}, &1))
    refute List.keymember?(headers, "authorization", 0)
  end

  test "make fills and exports in one go, defaulting the file name", ctx do
    authorize(ctx)
    {out, 0} = canva(ctx, ["make", "DAT1", "--text", "title=Hello", "--format", "png"])
    assert out =~ "design_id: DAdesign1"
    assert out =~ "./canva-DAdesign1.png"
    assert File.read!(Path.join(ctx.state, "canva-DAdesign1.png")) == "PNGDATA"
  end

  test "an invalid id, name or format is refused before any request", ctx do
    authorize(ctx)
    requests()

    for args <- [
          ["fields", "../etc"],
          ["fields", "a b"],
          ["fill", "DAT1/x", "--text", "title=x"],
          ["fill", "DAT1", "--text", "bad\"name=x"],
          ["fill", "DAT1", "--image", "photo=../x"],
          ["export", "DA;rm", "--format", "png"],
          ["export", "DAdesign1", "--format", "gif"],
          ["upload", "https://x.com/a b.jpg"],
          ["upload", "https://x.com/a.jpg", "bad/name"]
        ] do
      assert {out, 1} = canva(ctx, args), "expected #{inspect(args)} to fail"
      assert out =~ ~r/^canva: .+\n$/
    end

    assert requests() == []
  end

  test "a failed job gives a one-line error", ctx do
    authorize(ctx)
    assert {out, 1} = canva(ctx, ["fill", "DAT1", "--text", "title=FAILME"])
    assert out == "canva: autofill failed: trial_quota_exceeded: The autofill quota is used up\n"
  end

  test "a refused request gives a one-line error", ctx do
    authorize(ctx)
    File.write!(Path.join(ctx.state, "tokens.json"), tokens(ctx) |> Map.put("access_token", "WRONG") |> Jason.encode!())
    assert {out, 1} = canva(ctx, ["templates"])
    assert out == "canva: Canva refused GET /brand-templates: unauthorized: bad token\n"
  end

  test "using the script before authorizing says what to do", ctx do
    assert {out, 1} = canva(ctx, ["templates"])
    assert out =~ "not authorized yet"
  end

  test "no output of any command contains a token or the client secret", ctx do
    {url, 0} = canva(ctx, ["auth-url"])
    q = url |> String.trim() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    Agent.update(ctx.agent, &%{&1 | challenge: q["code_challenge"]})
    {code_out, 0} = canva(ctx, ["auth-code", "the-code"])

    {a, _} = canva(ctx, ["status"])
    {b, _} = canva(ctx, ["templates"])
    {c, _} = canva(ctx, ["fill", "DAT1", "--text", "title=FAILME"])
    {d, _} = canva(ctx, ["fields", "DAT1"])
    # a server that echoes the token back in an error must not get it through
    File.write!(
      Path.join(ctx.state, "tokens.json"),
      tokens(ctx) |> Map.put("expires_at", 0) |> Map.put("refresh_token", "RT-stale") |> Jason.encode!()
    )

    {e, 1} = canva(ctx, ["templates"])

    assert_no_secrets([url, code_out, a, b, c, d])
    refute e =~ @client_secret
  end
end
