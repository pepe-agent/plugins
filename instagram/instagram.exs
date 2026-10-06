# Instagram tools for Pepe, as a drop-in plugin (Instagram Graph API, for a Business or Creator account).
#
# Five tools: the account's details and how many posts it may still publish today, its recent posts
# with their likes and comments, and three that publish: a photo, a carousel, a reel. Each is an
# ordinary Pepe tool, so an agent holds exactly the ones it is given, and every publish still passes
# the permission gate.
#
# Instagram downloads the picture or video itself, from a public address, so the tools take URLs.
#
# Settings come from the plugin's Configure dialog, falling back to environment variables:
#
#   * access_token / INSTAGRAM_ACCESS_TOKEN   a long-lived token (a system user's token does not expire)
#   * ig_user_id   / INSTAGRAM_USER_ID        the Instagram account's id (not the @name)
#   * writes       / INSTAGRAM_WRITES         "yes" to let the agent publish; anything else = read only
#   * api_version  / INSTAGRAM_API_VERSION    the Graph API version, like v23.0
#
# INSTAGRAM_API_URL and INSTAGRAM_POLL_MS override the address and the wait between video checks
# (for a proxy or a test); they are not normal settings.

defmodule Pepe.Plugins.Instagram.Client do
  @moduledoc """
  Settings, the Graph API calls, and the publishing steps the tools share.
  """

  @default_version "v23.0"
  @max_caption 2200
  @max_polls 20

  # ---- settings ------------------------------------------------------------------------

  @doc "The connection settings, or `{:error, message}` naming what is missing."
  def settings do
    token = setting("access_token", "INSTAGRAM_ACCESS_TOKEN")
    user = setting("ig_user_id", "INSTAGRAM_USER_ID")

    cond do
      is_nil(token) or is_nil(user) ->
        {:error, "Instagram is not configured. Set the access token and the Instagram account id under Plugins -> Configure."}

      not Regex.match?(~r/\A\d+\z/, String.trim(user)) ->
        {:error, "The Instagram account id must be a number (like 17841400000000000), not the @name."}

      true ->
        base = (setting("api_url", "INSTAGRAM_API_URL") || "https://graph.facebook.com") |> String.trim() |> String.trim_trailing("/")
        version = setting("api_version", "INSTAGRAM_API_VERSION") || @default_version
        {:ok, %{base: base <> "/" <> version, token: token, user: String.trim(user)}}
    end
  end

  @doc "Publishing is off until the operator turns it on."
  def writable? do
    if setting("writes", "INSTAGRAM_WRITES") |> to_string() |> String.downcase() == "yes",
      do: :ok,
      else: {:error, "Publishing to Instagram is off. Set \"Allow publishing\" to yes under Plugins -> Configure."}
  end

  defp poll_ms do
    case Integer.parse(to_string(setting("poll_ms", "INSTAGRAM_POLL_MS") || "")) do
      {ms, ""} when ms >= 0 -> ms
      _ -> 3000
    end
  end

  defp setting(key, env_key), do: Pepe.Plugins.config("instagram", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  # ---- checking what the model sends ---------------------------------------------------------

  @doc "A public address for Instagram to download from."
  def url(value) do
    value = value |> to_string() |> String.trim()
    if Regex.match?(~r{\Ahttps://[^\s]+\z}, value), do: {:ok, value}, else: {:error, "#{inspect(value)} is not a public https address."}
  end

  @doc "A caption within Instagram's limit (nil for none)."
  def caption(nil), do: {:ok, nil}

  def caption(value) when is_binary(value) do
    if String.length(value) <= @max_caption,
      do: {:ok, blank(value)},
      else: {:error, "The caption has #{String.length(value)} characters; Instagram allows #{@max_caption}."}
  end

  def caption(_other), do: {:error, "The caption must be text."}

  def blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  def blank(_value), do: nil

  # ---- http ----------------------------------------------------------------------------

  def get(settings, path, params \\ []) do
    handle(Req.get(settings.base <> path, params: [access_token: settings.token] ++ params, receive_timeout: 30_000, retry: false))
  end

  def post(settings, path, params) do
    handle(Req.post(settings.base <> path, form: [access_token: settings.token] ++ params, receive_timeout: 60_000, retry: false))
  end

  defp handle({:ok, %{status: status, body: body}}) when status in 200..299, do: {:ok, body}
  defp handle({:ok, %{status: status, body: body}}), do: {:error, explain(status, body)}
  defp handle({:error, reason}), do: {:error, "Could not reach Instagram: #{inspect(reason)}"}

  defp explain(_status, %{"error" => %{"code" => 190}}),
    do: "Instagram did not accept the access token (it expired, was revoked, or the password changed). Create a new one."

  defp explain(_status, %{"error" => %{"code" => code}}) when code in [4, 17, 32, 613],
    do: "Instagram is rate limiting this account or app. Try again later."

  defp explain(_status, %{"error" => %{"code" => code} = error}) when code in [10, 200, 299],
    do: "The token lacks a permission for this#{detail(error)}"

  defp explain(status, %{"error" => error}), do: "Instagram refused it (#{status})#{detail(error)}"
  defp explain(status, _body), do: "Instagram answered with an error (#{status})."

  defp detail(error) do
    case error["error_user_msg"] || error["message"] do
      nil -> "."
      message -> ": " <> message
    end
  end

  # ---- publishing ----------------------------------------------------------------------

  @doc "Create a media container (a post waiting to be published)."
  def container(settings, params) do
    with {:ok, %{"id" => id}} <- post(settings, "/#{settings.user}/media", params), do: {:ok, id}
  end

  @doc "Wait for a video container to finish processing, then it can be published."
  def wait_ready(settings, container, tries \\ @max_polls) do
    case get(settings, "/#{container}", fields: "status_code,status") do
      {:ok, %{"status_code" => "FINISHED"}} ->
        :ok

      {:ok, %{"status_code" => code} = body} when code in ["ERROR", "EXPIRED"] ->
        {:error,
         "Instagram could not process the video (#{code}#{if body["status"], do: ": " <> to_string(body["status"])}). Check its format and size."}

      {:ok, _in_progress} when tries > 1 ->
        Process.sleep(poll_ms())
        wait_ready(settings, container, tries - 1)

      {:ok, _} ->
        {:error, "Instagram is still processing the video. It was not published; try again in a few minutes."}

      {:error, _} = error ->
        error
    end
  end

  @doc "Publish a ready container and give back the post's link."
  def publish(settings, container) do
    with {:ok, %{"id" => media_id}} <- post(settings, "/#{settings.user}/media_publish", creation_id: container) do
      case get(settings, "/#{media_id}", fields: "permalink") do
        {:ok, %{"permalink" => link}} -> {:ok, "Published: #{link}"}
        _ -> {:ok, "Published (post id #{media_id})."}
      end
    end
  end

  # ---- what comes back -------------------------------------------------------------------

  @doc """
  Text that came out of Instagram (captions) is written by whoever can post to the account, so it
  reaches the model framed as quoted material, never as instructions.
  """
  def external(text) do
    Pepe.Security.ExternalContent.mark_untrusted("instagram", Pepe.Security.ExternalContent.sanitize(text))
  end

  @doc "Cut a text to a length."
  def clip(text, max) do
    text = text |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(text) > max, do: String.slice(text, 0, max) <> "...", else: text
  end
end

defmodule Pepe.Plugins.InstagramAccount do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Instagram.Client

  @impl true
  def name, do: "instagram_account"

  @impl true
  def spec do
    function(
      "instagram_account",
      "Show the connected Instagram account (name, followers, number of posts) and how many posts it may still publish " <>
        "through the API in the last 24 hours.",
      %{"type" => "object", "properties" => %{}}
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(_args, _ctx) do
    with {:ok, settings} <- Client.settings(),
         {:ok, account} <- Client.get(settings, "/#{settings.user}", fields: "username,name,followers_count,follows_count,media_count") do
      quota =
        case Client.get(settings, "/#{settings.user}/content_publishing_limit", fields: "quota_usage,config") do
          {:ok, %{"data" => [%{"quota_usage" => used, "config" => %{"quota_total" => total}} | _]}} ->
            "Publishing in the last 24 hours: #{used} of #{total} used."

          _ ->
            "Publishing quota: not available."
        end

      lines = [
        "@#{account["username"]} (#{account["name"]})",
        "Followers: #{account["followers_count"]}   Following: #{account["follows_count"]}   Posts: #{account["media_count"]}",
        quota
      ]

      {:ok, lines |> Enum.join("\n") |> Client.external()}
    end
  end
end

defmodule Pepe.Plugins.InstagramRecentPosts do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Instagram.Client

  @impl true
  def name, do: "instagram_recent_posts"

  @impl true
  def spec do
    function("instagram_recent_posts", "List the account's most recent posts with their type, date, likes, comments and link.", %{
      "type" => "object",
      "properties" => %{"max" => %{"type" => "integer", "description" => "How many posts (1 to 25, default 10)."}}
    })
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(25) |> max(1), else: 10

    with {:ok, settings} <- Client.settings(),
         {:ok, body} <-
           Client.get(settings, "/#{settings.user}/media",
             fields: "id,caption,media_type,permalink,timestamp,like_count,comments_count",
             limit: max
           ) do
      case body["data"] do
        [_ | _] = posts -> {:ok, posts |> Enum.map_join("\n", &line/1) |> Client.external()}
        _ -> {:ok, "The account has no posts."}
      end
    end
  end

  defp line(post) do
    "#{String.slice(to_string(post["timestamp"]), 0, 10)} #{post["media_type"]}: #{post["like_count"] || 0} likes, " <>
      "#{post["comments_count"] || 0} comments. #{Client.clip(post["caption"] || "(no caption)", 90)}\n  #{post["permalink"]}"
  end
end

defmodule Pepe.Plugins.InstagramPublishPhoto do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Instagram.Client

  @impl true
  def name, do: "instagram_publish_photo"

  @impl true
  def spec do
    function(
      "instagram_publish_photo",
      "Publish a photo on the Instagram account, right now and for everyone to see. The picture must be a JPEG at a public " <>
        "https address. Gives back the post's link. A published post cannot be taken back through this tool.",
      %{
        "type" => "object",
        "properties" => %{
          "image_url" => %{"type" => "string", "description" => "Public https address of a JPEG image."},
          "caption" => %{"type" => "string", "description" => "The caption (up to 2200 characters, hashtags included)."}
        },
        "required" => ["image_url"]
      }
    )
  end

  @impl true
  def run(%{"image_url" => image_url} = args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, image_url} <- Client.url(image_url),
         {:ok, caption} <- Client.caption(args["caption"]),
         {:ok, settings} <- Client.settings(),
         {:ok, container} <- Client.container(settings, [image_url: image_url] ++ if(caption, do: [caption: caption], else: [])) do
      Client.publish(settings, container)
    end
  end

  def run(_args, _ctx), do: {:error, "instagram_publish_photo needs an `image_url`."}
end

defmodule Pepe.Plugins.InstagramPublishCarousel do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Instagram.Client

  @impl true
  def name, do: "instagram_publish_carousel"

  @impl true
  def spec do
    function(
      "instagram_publish_carousel",
      "Publish a carousel of 2 to 10 photos on the Instagram account, right now and for everyone to see. Every picture must be " <>
        "a JPEG at a public https address. Gives back the post's link. A published post cannot be taken back through this tool.",
      %{
        "type" => "object",
        "properties" => %{
          "image_urls" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "2 to 10 public https addresses of JPEG images, in order."
          },
          "caption" => %{"type" => "string", "description" => "The caption (up to 2200 characters, hashtags included)."}
        },
        "required" => ["image_urls"]
      }
    )
  end

  @impl true
  def run(%{"image_urls" => urls} = args, _ctx) when is_list(urls) do
    with :ok <- Client.writable?(),
         :ok <- count(urls),
         {:ok, urls} <- all_urls(urls),
         {:ok, caption} <- Client.caption(args["caption"]),
         {:ok, settings} <- Client.settings(),
         {:ok, children} <- items(settings, urls),
         {:ok, container} <-
           Client.container(
             settings,
             [media_type: "CAROUSEL", children: Enum.join(children, ",")] ++ if(caption, do: [caption: caption], else: [])
           ) do
      Client.publish(settings, container)
    end
  end

  def run(_args, _ctx), do: {:error, "instagram_publish_carousel needs a list of `image_urls`."}

  defp count(urls) when length(urls) in 2..10, do: :ok
  defp count(urls), do: {:error, "A carousel takes 2 to 10 pictures, not #{length(urls)}."}

  defp all_urls(urls) do
    Enum.reduce_while(urls, {:ok, []}, fn url, {:ok, acc} ->
      case Client.url(url) do
        {:ok, good} -> {:cont, {:ok, acc ++ [good]}}
        error -> {:halt, error}
      end
    end)
  end

  # One container per picture, created in order; if one fails nothing has been published.
  defp items(settings, urls) do
    Enum.reduce_while(urls, {:ok, []}, fn url, {:ok, acc} ->
      case Client.container(settings, image_url: url, is_carousel_item: true) do
        {:ok, id} -> {:cont, {:ok, acc ++ [id]}}
        error -> {:halt, error}
      end
    end)
  end
end

defmodule Pepe.Plugins.InstagramPublishReel do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.Instagram.Client

  @impl true
  def name, do: "instagram_publish_reel"

  @impl true
  def spec do
    function(
      "instagram_publish_reel",
      "Publish a reel (a short vertical video) on the Instagram account, right now and for everyone to see. The video must " <>
        "be at a public https address. Instagram processes it first, which can take a minute. Gives back the post's link. " <>
        "A published post cannot be taken back through this tool.",
      %{
        "type" => "object",
        "properties" => %{
          "video_url" => %{"type" => "string", "description" => "Public https address of an MP4 or MOV video."},
          "caption" => %{"type" => "string", "description" => "The caption (up to 2200 characters, hashtags included)."},
          "share_to_feed" => %{"type" => "boolean", "description" => "Also show it in the profile's main feed (default true)."}
        },
        "required" => ["video_url"]
      }
    )
  end

  @impl true
  def run(%{"video_url" => video_url} = args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, video_url} <- Client.url(video_url),
         {:ok, caption} <- Client.caption(args["caption"]),
         {:ok, settings} <- Client.settings(),
         params =
           [media_type: "REELS", video_url: video_url, share_to_feed: args["share_to_feed"] != false] ++
             if(caption, do: [caption: caption], else: []),
         {:ok, container} <- Client.container(settings, params),
         :ok <- Client.wait_ready(settings, container) do
      Client.publish(settings, container)
    end
  end

  def run(_args, _ctx), do: {:error, "instagram_publish_reel needs a `video_url`."}
end
