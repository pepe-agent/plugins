defmodule Pepe.Plugins.InstagramTest do
  @moduledoc """
  The Instagram plugin against a fake Graph API: the steps of publishing (a container, then
  publish), what each tool sends, how it reads the answers, and what it refuses to do. Nothing
  here talks to the real service.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.Instagram.Client
  alias Pepe.Plugins.InstagramAccount
  alias Pepe.Plugins.InstagramPublishCarousel
  alias Pepe.Plugins.InstagramPublishPhoto
  alias Pepe.Plugins.InstagramPublishReel
  alias Pepe.Plugins.InstagramRecentPosts

  @user "17841400000000000"

  defmodule FakeGraph do
    @moduledoc false
    import Plug.Conn

    @user "17841400000000000"

    def init(test), do: test

    def call(conn, test) do
      conn = fetch_query_params(conn)
      {:ok, raw, conn} = read_body(conn)
      form = if raw == "", do: %{}, else: URI.decode_query(raw)
      params = Map.merge(conn.query_params, form)
      send(test, {:request, conn.method, conn.request_path, params})

      case {conn.method, conn.request_path} do
        {"GET", "/v23.0/" <> @user} ->
          json(conn, 200, %{
            "username" => "caren.app",
            "name" => "Caren",
            "followers_count" => 1200,
            "follows_count" => 80,
            "media_count" => 54
          })

        {"GET", "/v23.0/" <> @user <> "/content_publishing_limit"} ->
          json(conn, 200, %{"data" => [%{"quota_usage" => 3, "config" => %{"quota_total" => 100}}]})

        {"GET", "/v23.0/" <> @user <> "/media"} ->
          json(conn, 200, %{
            "data" => [
              %{
                "id" => "p1",
                "caption" => "Launch day   \n #caren",
                "media_type" => "IMAGE",
                "permalink" => "https://instagram.com/p/AAA/",
                "timestamp" => "2026-10-02T10:00:00+0000",
                "like_count" => 40,
                "comments_count" => 3
              },
              %{
                "id" => "p2",
                "media_type" => "VIDEO",
                "permalink" => "https://instagram.com/reel/BBB/",
                "timestamp" => "2026-10-01T10:00:00+0000"
              }
            ]
          })

        {"POST", "/v23.0/" <> @user <> "/media"} ->
          container(conn, params)

        {"POST", "/v23.0/" <> @user <> "/media_publish"} ->
          json(conn, 200, %{"id" => "published-" <> params["creation_id"]})

        {"GET", "/v23.0/published-" <> _} ->
          json(conn, 200, %{"permalink" => "https://instagram.com/p/NEW/"})

        {"GET", "/v23.0/video-processing"} ->
          n = Agent.get_and_update(Process.whereis(:fake_graph_polls), &{&1, &1 + 1})
          json(conn, 200, %{"status_code" => if(n < 2, do: "IN_PROGRESS", else: "FINISHED")})

        {"GET", "/v23.0/video-broken"} ->
          json(conn, 200, %{"status_code" => "ERROR", "status" => "Video codec not supported"})

        _ ->
          json(conn, 400, %{"error" => %{"message" => "Invalid OAuth access token.", "code" => 190}})
      end
    end

    defp container(conn, %{"image_url" => "https://cdn.test/refused.jpg"}),
      do:
        json(conn, 400, %{
          "error" => %{"message" => "Media upload has failed", "code" => 9004, "error_user_msg" => "The image could not be downloaded."}
        })

    defp container(conn, %{"media_type" => "REELS", "video_url" => "https://cdn.test/slow.mp4"}),
      do: json(conn, 200, %{"id" => "video-processing"})

    defp container(conn, %{"media_type" => "REELS", "video_url" => "https://cdn.test/broken.mp4"}),
      do: json(conn, 200, %{"id" => "video-broken"})

    defp container(conn, %{"media_type" => "REELS"}), do: json(conn, 200, %{"id" => "video-processing"})

    defp container(conn, %{"is_carousel_item" => "true"} = p),
      do: json(conn, 200, %{"id" => "item-" <> Path.basename(p["image_url"], ".jpg")})

    defp container(conn, %{"media_type" => "CAROUSEL"}), do: json(conn, 200, %{"id" => "carousel-1"})
    defp container(conn, _params), do: json(conn, 200, %{"id" => "photo-1"})

    defp json(conn, status, data), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end

  setup do
    {:ok, _} = Agent.start_link(fn -> 0 end, name: :fake_graph_polls)
    {:ok, server} = Bandit.start_link(plug: {FakeGraph, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)

    Application.put_env(:pepe_plugins, :plugin_config, %{
      "instagram" => %{
        "access_token" => "tok-1",
        "ig_user_id" => @user,
        "api_url" => "http://127.0.0.1:#{port}",
        "writes" => "yes",
        "poll_ms" => "1"
      }
    })

    on_exit(fn -> Application.delete_env(:pepe_plugins, :plugin_config) end)
    :ok
  end

  describe "reading" do
    test "the account shows its details and what is left of the publishing quota" do
      assert {:ok, out} = InstagramAccount.run(%{}, %{})
      assert out =~ "@caren.app (Caren)"
      assert out =~ "Followers: 1200"
      assert out =~ "Publishing in the last 24 hours: 3 of 100 used."
      assert_received {:request, "GET", "/v23.0/" <> @user, %{"access_token" => "tok-1"}}
    end

    test "recent posts are listed with likes, comments, a short caption and the link" do
      assert {:ok, out} = InstagramRecentPosts.run(%{"max" => 2}, %{})
      assert out =~ "2026-10-02 IMAGE: 40 likes, 3 comments. Launch day #caren"
      assert out =~ "https://instagram.com/p/AAA/"
      assert out =~ "2026-10-01 VIDEO: 0 likes, 0 comments. (no caption)"
      assert_received {:request, "GET", _, %{"limit" => "2"}}
    end

    test "what comes out of Instagram is framed as external content, never as instructions" do
      {:ok, posts} = InstagramRecentPosts.run(%{}, %{})
      {:ok, account} = InstagramAccount.run(%{}, %{})
      for out <- [posts, account], do: assert(out =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: instagram")
      assert InstagramRecentPosts.outside_content?() and InstagramAccount.outside_content?()
    end
  end

  describe "publishing a photo" do
    test "creates a container with the picture and caption, publishes it, and gives back the link" do
      assert {:ok, out} = InstagramPublishPhoto.run(%{"image_url" => "https://cdn.test/a.jpg", "caption" => "Hello #caren"}, %{})
      assert out == "Published: https://instagram.com/p/NEW/"

      assert_received {:request, "POST", "/v23.0/" <> @user <> "/media",
                       %{"image_url" => "https://cdn.test/a.jpg", "caption" => "Hello #caren"}}

      assert_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", %{"creation_id" => "photo-1"}}
    end

    test "Instagram's own reason is what the agent is told when it cannot fetch the picture" do
      assert {:error, msg} = InstagramPublishPhoto.run(%{"image_url" => "https://cdn.test/refused.jpg"}, %{})
      assert msg =~ "The image could not be downloaded."
      refute_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", _}
    end

    test "an address that is not public https, or a caption that is too long, never reaches Instagram" do
      assert {:error, msg} = InstagramPublishPhoto.run(%{"image_url" => "http://cdn.test/a.jpg"}, %{})
      assert msg =~ "not a public https address"
      assert {:error, _} = InstagramPublishPhoto.run(%{"image_url" => "file:///etc/passwd"}, %{})

      assert {:error, long} =
               InstagramPublishPhoto.run(%{"image_url" => "https://cdn.test/a.jpg", "caption" => String.duplicate("a", 2201)}, %{})

      assert long =~ "2201 characters; Instagram allows 2200"
      refute_received {:request, _, _, _}
    end
  end

  describe "publishing a carousel" do
    test "creates one container per picture, then the carousel, then publishes it" do
      urls = ["https://cdn.test/1.jpg", "https://cdn.test/2.jpg", "https://cdn.test/3.jpg"]
      assert {:ok, out} = InstagramPublishCarousel.run(%{"image_urls" => urls, "caption" => "Three"}, %{})
      assert out =~ "Published:"

      for url <- urls, do: assert_received({:request, "POST", _, %{"is_carousel_item" => "true", "image_url" => ^url}})
      assert_received {:request, "POST", _, %{"media_type" => "CAROUSEL", "children" => "item-1,item-2,item-3", "caption" => "Three"}}
      assert_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", %{"creation_id" => "carousel-1"}}
    end

    test "fewer than 2 or more than 10 pictures is refused before any request" do
      assert {:error, one} = InstagramPublishCarousel.run(%{"image_urls" => ["https://cdn.test/1.jpg"]}, %{})
      assert one =~ "2 to 10 pictures, not 1"
      many = for n <- 1..11, do: "https://cdn.test/#{n}.jpg"
      assert {:error, _} = InstagramPublishCarousel.run(%{"image_urls" => many}, %{})
      refute_received {:request, _, _, _}
    end

    test "one bad picture stops it before the carousel is made or published" do
      urls = ["https://cdn.test/1.jpg", "https://cdn.test/refused.jpg"]
      assert {:error, _} = InstagramPublishCarousel.run(%{"image_urls" => urls}, %{})
      refute_received {:request, "POST", _, %{"media_type" => "CAROUSEL"}}
      refute_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", _}
    end
  end

  describe "publishing a reel" do
    test "waits for the video to be processed, then publishes it" do
      assert {:ok, out} =
               InstagramPublishReel.run(%{"video_url" => "https://cdn.test/slow.mp4", "caption" => "Reel", "share_to_feed" => false}, %{})

      assert out =~ "Published:"

      assert_received {:request, "POST", _,
                       %{"media_type" => "REELS", "video_url" => "https://cdn.test/slow.mp4", "share_to_feed" => "false"}}

      assert_received {:request, "GET", "/v23.0/video-processing", %{"fields" => "status_code,status"}}
      assert_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", %{"creation_id" => "video-processing"}}
    end

    test "a video Instagram cannot process is not published, and the agent is told why" do
      assert {:error, msg} = InstagramPublishReel.run(%{"video_url" => "https://cdn.test/broken.mp4"}, %{})
      assert msg =~ "could not process the video (ERROR: Video codec not supported)"
      refute_received {:request, "POST", "/v23.0/" <> @user <> "/media_publish", _}
    end
  end

  describe "publishing is off until it is turned on" do
    setup do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["instagram", "writes"], "no"))
      :ok
    end

    test "every publish is refused before any request, and reading still works" do
      assert {:error, msg} = InstagramPublishPhoto.run(%{"image_url" => "https://cdn.test/a.jpg"}, %{})
      assert msg =~ "Publishing to Instagram is off"
      assert {:error, _} = InstagramPublishCarousel.run(%{"image_urls" => ["https://cdn.test/1.jpg", "https://cdn.test/2.jpg"]}, %{})
      assert {:error, _} = InstagramPublishReel.run(%{"video_url" => "https://cdn.test/a.mp4"}, %{})
      refute_received {:request, _, _, _}
      assert {:ok, _} = InstagramAccount.run(%{}, %{})
    end
  end

  describe "when Instagram says no" do
    test "a token that expired says to create a new one" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["instagram", "api_version"], "v1.0"))
      assert {:error, msg} = InstagramAccount.run(%{}, %{})
      assert msg =~ "did not accept the access token"
    end

    test "an account id that is the @name is refused with how to fix it" do
      config = Application.get_env(:pepe_plugins, :plugin_config)
      Application.put_env(:pepe_plugins, :plugin_config, put_in(config, ["instagram", "ig_user_id"], "@caren.app"))
      assert {:error, msg} = InstagramAccount.run(%{}, %{})
      assert msg =~ "must be a number"
    end

    test "no settings at all says what to fill in" do
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = Client.settings()
      assert msg =~ "Instagram is not configured"
    end
  end
end
