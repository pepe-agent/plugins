# Meta Ads: the tools that CREATE. Everything made here is PAUSED: nothing is shown to anyone and
# nothing is spent until it is turned on (by a person in Ads Manager, or by meta_ads_set_status when
# the operator allowed that). See meta-ads.exs for the settings and the shared client.

defmodule Pepe.Plugins.MetaAdsBuild do
  @moduledoc """
  Checks what the model sent and turns it into the parameters Meta takes, for the tools that create
  a campaign, an ad set, a creative and an ad. Shared, so the one-call draft and the step-by-step
  tools agree. Everything is validated before the first request, so a mistake never costs a call.
  """

  alias Pepe.Plugins.MetaAds.Client

  @objectives %{
    "traffic" => "OUTCOME_TRAFFIC",
    "awareness" => "OUTCOME_AWARENESS",
    "engagement" => "OUTCOME_ENGAGEMENT",
    "leads" => "OUTCOME_LEADS",
    "sales" => "OUTCOME_SALES",
    "app_promotion" => "OUTCOME_APP_PROMOTION"
  }

  @categories %{
    "none" => [],
    "housing" => ["HOUSING"],
    "employment" => ["EMPLOYMENT"],
    "credit" => ["CREDIT"],
    "politics" => ["ISSUES_ELECTIONS_POLITICS"]
  }

  @goals ~w(REACH IMPRESSIONS LINK_CLICKS LANDING_PAGE_VIEWS POST_ENGAGEMENT PAGE_LIKES LEAD_GENERATION QUALITY_LEAD OFFSITE_CONVERSIONS VALUE CONVERSATIONS APP_INSTALLS THRUPLAY VIDEO_VIEWS AD_RECALL_LIFT)
  @billing ~w(IMPRESSIONS LINK_CLICKS THRUPLAY)
  @destinations ~w(WEBSITE ON_AD ON_POST ON_PAGE ON_VIDEO MESSENGER WHATSAPP INSTAGRAM_DIRECT APP)
  @bid_strategies ~w(LOWEST_COST_WITHOUT_CAP LOWEST_COST_WITH_BID_CAP COST_CAP LOWEST_COST_WITH_MIN_ROAS)
  @events ~w(PURCHASE LEAD COMPLETE_REGISTRATION ADD_TO_CART INITIATE_CHECKOUT CONTACT SUBSCRIBE VIEW_CONTENT SEARCH ADD_PAYMENT_INFO OTHER)
  @needs_page ~w(LEAD_GENERATION QUALITY_LEAD CONVERSATIONS PAGE_LIKES)
  @buttons ~w(LEARN_MORE SHOP_NOW SIGN_UP CONTACT_US BOOK_TRAVEL DOWNLOAD GET_QUOTE SUBSCRIBE APPLY_NOW ORDER_NOW WATCH_MORE SEND_MESSAGE WHATSAPP_MESSAGE GET_OFFER INSTALL_MOBILE_APP NO_BUTTON)

  def objectives, do: Map.keys(@objectives)
  def categories, do: Map.keys(@categories)
  def goals, do: @goals
  def billing, do: @billing
  def destinations, do: @destinations
  def bid_strategies, do: @bid_strategies
  def events, do: @events
  def buttons, do: @buttons

  # ---- campaign ----------------------------------------------------------------------------

  @doc "The parameters of a paused campaign."
  def campaign(args, currency) do
    with {:ok, objective} <- Client.one_of(args["objective"], objectives(), "objective"),
         {:ok, category} <- Client.one_of(args["special_ad_category"], categories(), "special_ad_category"),
         {:ok, name} <- text(args["name"], "name", 200),
         {:ok, budget} <- budget(args["daily_budget"], nil, currency, nil, nil),
         {:ok, strategy} <- optional_one_of(args["bid_strategy"], @bid_strategies, "bid_strategy"),
         {:ok, spend_cap} <- spend_cap(args["spend_cap"], currency) do
      {:ok,
       [name: name, objective: @objectives[objective], status: "PAUSED", special_ad_categories: Jason.encode!(@categories[category])] ++
         budget ++ if(budget != [], do: [bid_strategy: strategy || "LOWEST_COST_WITHOUT_CAP"], else: []) ++ spend_cap}
    end
  end

  defp spend_cap(nil, _currency), do: {:ok, []}

  defp spend_cap(amount, currency) when is_number(amount) and amount > 0, do: {:ok, [spend_cap: Client.to_minor(amount, currency)]}
  defp spend_cap(_other, _currency), do: {:error, "`spend_cap` must be a number above zero (whole units)."}

  # ---- ad set ------------------------------------------------------------------------------

  @doc "The parameters of a paused ad set."
  def adset(args, currency, account_page) do
    with {:ok, campaign_id} <- Client.id(args["campaign_id"], "campaign id"),
         {:ok, name} <- text(args["name"], "name", 200),
         {:ok, goal} <- Client.one_of(args["optimization_goal"], @goals, "optimization_goal"),
         {:ok, billing} <- Client.one_of(args["billing_event"] || "IMPRESSIONS", @billing, "billing_event"),
         {:ok, destination} <- optional_one_of(args["destination_type"], @destinations, "destination_type"),
         {:ok, start} <- Client.optional_date(args["start_date"]),
         {:ok, finish} <- Client.optional_date(args["end_date"]),
         :ok <- order(start, finish),
         {:ok, budget} <- budget(args["daily_budget"], args["lifetime_budget"], currency, start, finish),
         {:ok, strategy} <- optional_one_of(args["bid_strategy"], @bid_strategies, "bid_strategy"),
         {:ok, bid} <- bid(args["bid_amount"], strategy, currency),
         {:ok, promoted} <- promoted(args, goal, account_page),
         {:ok, targeting} <- Client.targeting(args) do
      {:ok,
       [
         name: name,
         campaign_id: campaign_id,
         optimization_goal: goal,
         billing_event: billing,
         targeting: Jason.encode!(targeting),
         status: "PAUSED"
       ] ++
         budget ++
         if(budget != [],
           do: [bid_strategy: strategy || "LOWEST_COST_WITHOUT_CAP"],
           else: if(strategy, do: [bid_strategy: strategy], else: [])
         ) ++
         bid ++
         if(destination, do: [destination_type: destination], else: []) ++
         if(promoted, do: [promoted_object: Jason.encode!(promoted)], else: []) ++
         if(start, do: [start_time: start], else: []) ++ if(finish, do: [end_time: finish], else: [])}
    end
  end

  defp order(start, finish) when is_binary(start) and is_binary(finish) and finish < start,
    do: {:error, "`end_date` is before `start_date`."}

  defp order(_start, _finish), do: :ok

  # A bid cap or cost cap needs the amount; the other strategies refuse one.
  defp bid(nil, strategy, _currency) when strategy in ["LOWEST_COST_WITH_BID_CAP", "COST_CAP"],
    do: {:error, "`bid_strategy` #{strategy} needs a `bid_amount` (whole units)."}

  defp bid(nil, _strategy, _currency), do: {:ok, []}

  defp bid(amount, strategy, currency) when is_number(amount) and amount > 0 and strategy in ["LOWEST_COST_WITH_BID_CAP", "COST_CAP"],
    do: {:ok, [bid_amount: Client.to_minor(amount, currency)]}

  defp bid(_amount, _strategy, _currency),
    do: {:error, "`bid_amount` is only for the bid cap and cost cap strategies, and must be a number above zero."}

  # What the ad set tells Meta it is for: a Page, a pixel and the event to count, or an app.
  defp promoted(args, goal, default_page) do
    with {:ok, pixel} <- Client.optional_id(args["pixel_id"], "pixel id"),
         {:ok, app} <- Client.optional_id(args["application_id"], "application id"),
         {:ok, event} <- optional_one_of(args["custom_event_type"], @events, "custom_event_type"),
         {:ok, store} <- store_url(args["object_store_url"]),
         {:ok, page} <- page_for(goal, args["page_id"], default_page) do
      cond do
        goal in ["OFFSITE_CONVERSIONS", "VALUE"] and (is_nil(pixel) or is_nil(event)) ->
          {:error, "A conversion goal needs the `pixel_id` and the `custom_event_type` to count (like PURCHASE or LEAD)."}

        goal == "APP_INSTALLS" and (is_nil(app) or is_nil(store)) ->
          {:error, "App installs need the `application_id` and the `object_store_url` of the app."}

        true ->
          promoted =
            %{}
            |> Client.put("page_id", page)
            |> Client.put("pixel_id", pixel)
            |> Client.put("custom_event_type", event)
            |> Client.put("application_id", app)
            |> Client.put("object_store_url", store)

          {:ok, if(promoted == %{}, do: nil, else: promoted)}
      end
    end
  end

  defp page_for(goal, given, default) when goal in @needs_page,
    do: if(Client.blank(given), do: Client.id(given, "Facebook Page id"), else: default_page(default))

  defp page_for(_goal, given, _default), do: Client.optional_id(given, "Facebook Page id")

  defp default_page({:ok, page}), do: {:ok, page}
  defp default_page(other), do: other

  defp store_url(nil), do: {:ok, nil}
  defp store_url(value), do: Client.https(value, "object_store_url")

  # ---- budgets -----------------------------------------------------------------------------

  @doc """
  A daily or lifetime budget, in the smallest unit, checked against the operator's ceiling. A
  lifetime budget needs an end date, and may be at most the daily ceiling times the days it runs.
  """
  def budget(nil, nil, _currency, _start, _finish), do: {:ok, []}

  def budget(daily, nil, currency, _start, _finish) when is_number(daily) and daily > 0 do
    with {:ok, cap} <- Client.max_daily_budget() do
      if daily <= cap,
        do: {:ok, [daily_budget: Client.to_minor(daily, currency)]},
        else:
          {:error,
           "A daily budget of #{Client.fmt(daily)} is above the highest allowed (#{Client.fmt(cap)}). Ask for a lower one, or have the operator raise the limit."}
    end
  end

  def budget(nil, lifetime, currency, start, finish) when is_number(lifetime) and lifetime > 0 do
    with {:ok, cap} <- Client.max_daily_budget(),
         {:ok, days} <- days(start, finish) do
      if lifetime <= cap * days,
        do: {:ok, [lifetime_budget: Client.to_minor(lifetime, currency)]},
        else:
          {:error,
           "A lifetime budget of #{Client.fmt(lifetime)} over #{days} day(s) is above the highest allowed (#{Client.fmt(cap)} a day, #{Client.fmt(cap * days)} in all)."}
    end
  end

  def budget(daily, lifetime, _currency, _start, _finish) when not is_nil(daily) and not is_nil(lifetime),
    do: {:error, "Give a daily budget or a lifetime budget, not both."}

  def budget(_daily, _lifetime, _currency, _start, _finish), do: {:error, "A budget must be a number above zero (whole units, like 30)."}

  defp days(_start, nil), do: {:error, "A lifetime budget needs an `end_date`."}

  defp days(start, finish) do
    from = if start, do: Date.from_iso8601!(start), else: Date.utc_today()
    {:ok, max(1, Date.diff(Date.from_iso8601!(finish), from) + 1)}
  end

  # ---- creative ----------------------------------------------------------------------------

  @kinds ~w(link video carousel post)

  def kinds, do: @kinds

  @doc "The parameters of a creative (the picture or video, the text and the button of an ad)."
  def creative(args, page, instagram) do
    with {:ok, kind} <- Client.one_of(args["kind"] || "link", @kinds, "kind"),
         {:ok, name} <- text(args["name"], "name", 200),
         {:ok, tags} <- url_tags(args["url_tags"]),
         {:ok, spec} <- spec(kind, args, page) do
      {:ok, [name: name] ++ spec ++ if(instagram, do: [instagram_user_id: instagram], else: []) ++ if(tags, do: [url_tags: tags], else: [])}
    end
  end

  defp spec("link", args, page) do
    with {:ok, link} <- Client.https(args["link"], "link"),
         {:ok, message} <- text(args["message"], "message", 2200),
         {:ok, button} <- button(args["call_to_action"]),
         {:ok, picture} <- optional_https(args["image_url"], "image_url") do
      data =
        %{"link" => link, "message" => message, "call_to_action" => %{"type" => button, "value" => %{"link" => link}}}
        |> Client.put("name", Client.blank(args["headline"]))
        |> Client.put("description", Client.blank(args["description"]))
        |> Client.put("picture", picture)

      {:ok, [object_story_spec: Jason.encode!(%{"page_id" => page, "link_data" => data})]}
    end
  end

  defp spec("video", args, page) do
    with {:ok, video} <- Client.id(args["video_id"], "video id"),
         {:ok, link} <- Client.https(args["link"], "link"),
         {:ok, message} <- text(args["message"], "message", 2200),
         {:ok, button} <- button(args["call_to_action"]),
         {:ok, thumbnail} <- optional_https(args["image_url"], "image_url") do
      data =
        %{"video_id" => video, "message" => message, "call_to_action" => %{"type" => button, "value" => %{"link" => link}}}
        |> Client.put("title", Client.blank(args["headline"]))
        |> Client.put("link_description", Client.blank(args["description"]))
        |> Client.put("image_url", thumbnail)

      {:ok, [object_story_spec: Jason.encode!(%{"page_id" => page, "video_data" => data})]}
    end
  end

  defp spec("carousel", args, page) do
    with {:ok, link} <- Client.https(args["link"], "link"),
         {:ok, message} <- text(args["message"], "message", 2200),
         {:ok, cards} <- cards(args["cards"]) do
      {:ok,
       [
         object_story_spec:
           Jason.encode!(%{"page_id" => page, "link_data" => %{"link" => link, "message" => message, "child_attachments" => cards}})
       ]}
    end
  end

  defp spec("post", args, _page) do
    case {Client.blank(args["facebook_post_id"]), Client.blank(args["instagram_media_id"])} do
      {post, nil} when is_binary(post) ->
        if Regex.match?(~r/\A\d+_\d+\z/, post),
          do: {:ok, [object_story_id: post]},
          else: {:error, "`facebook_post_id` must look like 123456_7890123 (the Page id, an underscore, the post id)."}

      {nil, media} when is_binary(media) ->
        with {:ok, id} <- Client.id(media, "Instagram media id"), do: {:ok, [source_instagram_media_id: id]}

      _ ->
        {:error, "A post creative needs either `facebook_post_id` or `instagram_media_id`."}
    end
  end

  defp cards(list) when is_list(list) and length(list) in 2..10 do
    Enum.reduce_while(list, {:ok, []}, fn card, {:ok, acc} ->
      with true <- is_map(card),
           {:ok, link} <- Client.https(card["link"], "cards[].link"),
           {:ok, picture} <- optional_https(card["image_url"], "cards[].image_url"),
           {:ok, button} <- button(card["call_to_action"]) do
        entry =
          %{"link" => link, "call_to_action" => %{"type" => button, "value" => %{"link" => link}}}
          |> Client.put("name", Client.blank(card["headline"]))
          |> Client.put("description", Client.blank(card["description"]))
          |> Client.put("picture", picture)

        {:cont, {:ok, acc ++ [entry]}}
      else
        false -> {:halt, {:error, "Each card must be an object with a `link`."}}
        error -> {:halt, error}
      end
    end)
  end

  defp cards(_other), do: {:error, "A carousel needs 2 to 10 `cards`, each with a `link` and usually an `image_url` and a `headline`."}

  defp url_tags(nil), do: {:ok, nil}

  defp url_tags(value) do
    case Client.blank(value) do
      nil ->
        {:ok, nil}

      tags ->
        if Regex.match?(~r/\A[\w.\-=&%{}]+\z/, tags),
          do: {:ok, tags},
          else: {:error, "`url_tags` must look like utm_source=meta&utm_medium=paid."}
    end
  end

  # ---- ad ----------------------------------------------------------------------------------

  @doc "The parameters of a paused ad."
  def ad(args) do
    with {:ok, name} <- text(args["name"], "name", 200),
         {:ok, adset} <- Client.id(args["adset_id"], "ad set id"),
         {:ok, creative} <- Client.id(args["creative_id"], "creative id") do
      {:ok, [name: name, adset_id: adset, creative: Jason.encode!(%{"creative_id" => creative}), status: "PAUSED"]}
    end
  end

  # ---- small checks ----------------------------------------------------------------------

  def button(nil), do: {:ok, "LEARN_MORE"}
  def button(value), do: Client.one_of(value, @buttons, "call_to_action")

  defp optional_https(nil, _field), do: {:ok, nil}
  defp optional_https(value, field), do: if(Client.blank(value), do: Client.https(value, field), else: {:ok, nil})

  defp optional_one_of(nil, _allowed, _field), do: {:ok, nil}
  defp optional_one_of(value, allowed, field), do: Client.one_of(value, allowed, field)

  defp text(value, field, max) when is_binary(value) and value != "" do
    if String.length(value) <= max, do: {:ok, value}, else: {:error, "`#{field}` is too long (#{max} characters at most)."}
  end

  defp text(_value, field, _max), do: {:error, "`#{field}` is required."}
end

defmodule Pepe.Plugins.MetaAdsCreateCampaign do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  @impl true
  def name, do: "meta_ads_create_campaign"

  @impl true
  def spec do
    function(
      "meta_ads_create_campaign",
      "Create a Meta ad campaign, PAUSED. A campaign holds the objective; the budget and audience live in its ad sets " <>
        "(create them with meta_ads_create_adset). Give a daily_budget here only to share one budget across the ad sets.",
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "objective" => %{"type" => "string", "enum" => MetaAdsBuild.objectives(), "description" => "What the campaign is for."},
          "special_ad_category" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.categories(),
            "description" => "none, or housing, employment, credit or politics when the ads are about that. Required: ask when unsure."
          },
          "daily_budget" => %{"type" => "number", "description" => "Optional: one daily budget shared by all ad sets, in whole units."},
          "bid_strategy" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.bid_strategies(),
            "description" => "Optional, with a shared budget."
          },
          "spend_cap" => %{"type" => "number", "description" => "Optional: stop the campaign after this much total spend, in whole units."},
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
        },
        "required" => ["name", "objective", "special_ad_category"]
      }
    )
  end

  @impl true
  def run(args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, currency} <- Client.currency(settings, account),
         {:ok, params} <- MetaAdsBuild.campaign(args, currency),
         {:ok, %{"id" => id}} <- Client.post(settings, "/#{account}/campaigns", params) do
      {:ok, "Campaign created, PAUSED: #{id}. Next, create its ad sets with meta_ads_create_adset."}
    end
  end
end

defmodule Pepe.Plugins.MetaAdsCreateAdset do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  @impl true
  def name, do: "meta_ads_create_adset"

  @impl true
  def spec do
    function(
      "meta_ads_create_adset",
      "Create an ad set inside a campaign, PAUSED: who sees the ads (audience), where (placements), for how long, with what " <>
        "budget and what it optimizes for. Use meta_ads_search_targeting for interest, city and region ids and meta_ads_estimate " <>
        "to size the audience first. Leave the budget out when the campaign has a shared one.",
      %{
        "type" => "object",
        "properties" => %{
          "campaign_id" => %{"type" => "string"},
          "name" => %{"type" => "string"},
          "optimization_goal" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.goals(),
            "description" => "What delivery aims for, matching the campaign's objective (like LINK_CLICKS for traffic)."
          },
          "billing_event" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.billing(),
            "description" => "What is charged for (default IMPRESSIONS)."
          },
          "destination_type" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.destinations(),
            "description" => "Where people go (optional; WEBSITE for traffic and conversions)."
          },
          "daily_budget" => %{"type" => "number", "description" => "Whole units, like 30. Or lifetime_budget, not both."},
          "lifetime_budget" => %{"type" => "number", "description" => "Whole units over the whole run; needs end_date."},
          "bid_strategy" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.bid_strategies(),
            "description" => "Default lowest cost. Caps need bid_amount."
          },
          "bid_amount" => %{"type" => "number", "description" => "For a bid cap or cost cap, in whole units."},
          "start_date" => %{"type" => "string", "description" => "YYYY-MM-DD (optional)."},
          "end_date" => %{"type" => "string", "description" => "YYYY-MM-DD (optional, required for a lifetime budget)."},
          "countries" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Two-letter country codes."},
          "regions" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Region keys."},
          "cities" => %{"type" => "array", "description" => "City keys, or {key, radius in km (17 to 80)}."},
          "age_min" => %{"type" => "integer", "description" => "18 to 65 (default 18)."},
          "age_max" => %{"type" => "integer", "description" => "18 to 65 (default 65)."},
          "gender" => %{"type" => "string", "enum" => ["all", "men", "women"]},
          "interests" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Interest ids."},
          "behaviors" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Behavior ids."},
          "custom_audiences" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Audience ids to include."},
          "excluded_custom_audiences" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Audience ids to leave out."
          },
          "locales" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Language ids."},
          "advantage_audience" => %{
            "type" => "boolean",
            "description" => "Let Meta widen the audience beyond what you set (default false)."
          },
          "placements" => %{
            "description" =>
              "\"automatic\" (default), or {platforms: [facebook, instagram, audience_network, messenger], facebook_positions: [...], instagram_positions: [...]}."
          },
          "pixel_id" => %{"type" => "string", "description" => "For conversion goals."},
          "custom_event_type" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.events(),
            "description" => "The event to count, with pixel_id."
          },
          "application_id" => %{"type" => "string", "description" => "For app installs."},
          "object_store_url" => %{"type" => "string", "description" => "The app's store address, for app installs."},
          "page_id" => %{"type" => "string", "description" => "For lead, message and page-like goals (default: the configured Page)."},
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
        },
        "required" => ["campaign_id", "name", "optimization_goal"]
      }
    )
  end

  @impl true
  def run(args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, currency} <- Client.currency(settings, account),
         {:ok, params} <- MetaAdsBuild.adset(args, currency, Client.page_id(nil)),
         {:ok, %{"id" => id}} <- Client.post(settings, "/#{account}/adsets", params) do
      {:ok, "Ad set created, PAUSED: #{id}. Next, create a creative and an ad for it."}
    end
  end
end

defmodule Pepe.Plugins.MetaAdsUploadVideo do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_upload_video"

  @impl true
  def spec do
    function(
      "meta_ads_upload_video",
      "Add a video to the ad account from a public https address (Meta downloads it). Gives back the video id to use in a video creative. Meta processes it for a few minutes.",
      %{
        "type" => "object",
        "properties" => %{
          "video_url" => %{"type" => "string", "description" => "Public https address of an MP4 or MOV video."},
          "name" => %{"type" => "string", "description" => "A name for the video (optional)."},
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
        },
        "required" => ["video_url"]
      }
    )
  end

  @impl true
  def run(%{"video_url" => url} = args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, url} <- Client.https(url, "video_url"),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, %{"id" => id}} <-
           Client.post(
             settings,
             "/#{account}/advideos",
             [file_url: url] ++ if(Client.blank(args["name"]), do: [name: args["name"]], else: [])
           ) do
      {:ok, "Video added: #{id}. Meta is still processing it; wait a few minutes before using it in a creative."}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_upload_video needs a `video_url`."}
end

defmodule Pepe.Plugins.MetaAdsCreateCreative do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  @impl true
  def name, do: "meta_ads_create_creative"

  @impl true
  def spec do
    function(
      "meta_ads_create_creative",
      "Create an ad creative (what people see): a link ad with a picture, a video ad, a carousel of cards, or an existing " <>
        "Facebook or Instagram post to promote. It is not shown anywhere until an ad uses it.",
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "kind" => %{"type" => "string", "enum" => MetaAdsBuild.kinds(), "description" => "link (default), video, carousel or post."},
          "link" => %{"type" => "string", "description" => "Where people go (https). For link, video and carousel."},
          "message" => %{"type" => "string", "description" => "The main text."},
          "headline" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "image_url" => %{"type" => "string", "description" => "Public https address of the picture (a link ad) or the video's thumbnail."},
          "video_id" => %{"type" => "string", "description" => "From meta_ads_upload_video. For the video kind."},
          "cards" => %{
            "type" => "array",
            "description" => "2 to 10 cards, each {link, image_url, headline, description, call_to_action}. For carousel."
          },
          "facebook_post_id" => %{"type" => "string", "description" => "pageid_postid, to promote an existing Facebook post."},
          "instagram_media_id" => %{"type" => "string", "description" => "To promote an existing Instagram post."},
          "call_to_action" => %{"type" => "string", "enum" => MetaAdsBuild.buttons(), "description" => "The button (default LEARN_MORE)."},
          "url_tags" => %{
            "type" => "string",
            "description" => "Tracking added to the link, like utm_source=meta&utm_medium=paid&utm_campaign=launch."
          },
          "page_id" => %{"type" => "string", "description" => "The Facebook Page it runs as (default: the configured Page)."},
          "instagram_user_id" => %{"type" => "string", "description" => "The Instagram account it runs as (default: the configured one)."},
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
        },
        "required" => ["name"]
      }
    )
  end

  @impl true
  def run(args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, page} <- Client.page_id(args["page_id"]),
         {:ok, instagram} <- Client.instagram_user_id(args["instagram_user_id"]),
         {:ok, params} <- MetaAdsBuild.creative(args, page, instagram),
         {:ok, settings} <- Client.settings(),
         {:ok, %{"id" => id}} <- Client.post(settings, "/#{account}/adcreatives", params) do
      {:ok, "Creative created: #{id}. Next, create an ad that uses it."}
    end
  end
end

defmodule Pepe.Plugins.MetaAdsCreateAd do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  @impl true
  def name, do: "meta_ads_create_ad"

  @impl true
  def spec do
    function("meta_ads_create_ad", "Create an ad, PAUSED, from a creative inside an ad set. Gives back its id and a link to review it.", %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string"},
        "adset_id" => %{"type" => "string"},
        "creative_id" => %{"type" => "string"},
        "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
      },
      "required" => ["name", "adset_id", "creative_id"]
    })
  end

  @impl true
  def run(args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, params} <- MetaAdsBuild.ad(args),
         {:ok, settings} <- Client.settings(),
         {:ok, %{"id" => id}} <- Client.post(settings, "/#{account}/ads", params) do
      {:ok, "Ad created, PAUSED: #{id}. Review it with meta_ads_preview, then turn it on in Ads Manager."}
    end
  end
end

defmodule Pepe.Plugins.MetaAdsCreateDraft do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  # What each simple objective optimizes for, and what its ad set needs.
  @plans %{
    "traffic" => %{goal: "LINK_CLICKS", destination: "WEBSITE", event: nil},
    "awareness" => %{goal: "REACH", destination: nil, event: nil},
    "sales" => %{goal: "OFFSITE_CONVERSIONS", destination: "WEBSITE", event: "PURCHASE"},
    "leads" => %{goal: "OFFSITE_CONVERSIONS", destination: "WEBSITE", event: "LEAD"}
  }

  @impl true
  def name, do: "meta_ads_create_draft"

  @impl true
  def spec do
    function(
      "meta_ads_create_draft",
      "Create a whole Meta ad as a DRAFT in one go: campaign, ad set (budget, audience), creative (picture, text, link) and ad, " <>
        "all PAUSED. For the common case: a link ad for traffic, awareness, website sales or website leads. For anything else (video, " <>
        "carousel, promoting a post, special audiences, placements) use the step-by-step tools. Nothing is shown or spent until " <>
        "a person turns it on. Ask the user for what you do not know; do not guess the special ad category.",
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "A name for the campaign (the ad set, creative and ad are named from it)."},
          "objective" => %{
            "type" => "string",
            "enum" => Map.keys(@plans),
            "description" => "traffic, awareness, sales or leads (the last two count conversions and need pixel_id)."
          },
          "special_ad_category" => %{
            "type" => "string",
            "enum" => MetaAdsBuild.categories(),
            "description" => "none, or housing, employment, credit, politics. Required."
          },
          "daily_budget" => %{"type" => "number", "description" => "Whole units of the account's currency, like 30."},
          "countries" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Two-letter country codes, like [\"BR\"]."},
          "link" => %{"type" => "string", "description" => "The https address people go to."},
          "message" => %{"type" => "string", "description" => "The ad's main text."},
          "headline" => %{"type" => "string"},
          "image_url" => %{"type" => "string", "description" => "Public https address of the picture."},
          "call_to_action" => %{"type" => "string", "enum" => MetaAdsBuild.buttons()},
          "pixel_id" => %{"type" => "string", "description" => "For sales and leads."},
          "age_min" => %{"type" => "integer"},
          "age_max" => %{"type" => "integer"},
          "gender" => %{"type" => "string", "enum" => ["all", "men", "women"]},
          "interests" => %{"type" => "array", "items" => %{"type" => "string"}},
          "start_date" => %{"type" => "string"},
          "end_date" => %{"type" => "string"},
          "url_tags" => %{"type" => "string"},
          "account" => %{"type" => "string"},
          "page_id" => %{"type" => "string"}
        },
        "required" => ["name", "objective", "special_ad_category", "daily_budget", "countries", "link", "message"]
      }
    )
  end

  @impl true
  def run(%{"name" => name} = args, _ctx) when is_binary(name) and name != "" do
    with :ok <- Client.writable?(),
         {:ok, objective} <- Client.one_of(args["objective"], Map.keys(@plans), "objective"),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, page} <- Client.page_id(args["page_id"]),
         {:ok, instagram} <- Client.instagram_user_id(nil),
         {:ok, settings} <- Client.settings(),
         {:ok, currency} <- Client.currency(settings, account),
         {:ok, campaign_params} <-
           MetaAdsBuild.campaign(Map.take(args, ["name", "special_ad_category"]) |> Map.put("objective", objective), currency),
         {:ok, creative_params} <- MetaAdsBuild.creative(creative_args(args, name), page, instagram),
         {:ok, adset_template} <- adset_args(args, objective, name),
         # Checked now, before anything is created, so a mistake in the audience or the budget costs nothing.
         {:ok, _checked} <- MetaAdsBuild.adset(Map.put(adset_template, "campaign_id", "1"), currency, {:ok, page}) do
      create(settings, account, currency, page, campaign_params, adset_template, creative_params, name)
    end
  end

  def run(_args, _ctx),
    do:
      {:error,
       "meta_ads_create_draft needs a `name`, an `objective`, a `special_ad_category`, a `daily_budget`, `countries`, a `link` and a `message`."}

  defp creative_args(args, name) do
    args
    |> Map.take(["link", "message", "headline", "image_url", "call_to_action", "url_tags"])
    |> Map.merge(%{"name" => name <> ": creative", "kind" => "link"})
  end

  defp adset_args(args, objective, name) do
    plan = @plans[objective]

    base =
      args
      |> Map.take(~w(countries age_min age_max gender interests daily_budget start_date end_date pixel_id))
      |> Map.merge(%{"name" => name <> ": ad set", "optimization_goal" => plan.goal})
      |> then(&if(plan.destination, do: Map.put(&1, "destination_type", plan.destination), else: &1))
      |> then(&if(plan.event, do: Map.put(&1, "custom_event_type", plan.event), else: &1))

    {:ok, base}
  end

  # Each step is checked and sent in turn; a failure undoes what was made, so nothing half-built stays.
  defp create(settings, account, currency, page, campaign_params, adset_template, creative_params, name) do
    steps = [
      {:campaign, fn _made -> Client.post(settings, "/#{account}/campaigns", campaign_params) end},
      {:adset, fn made -> adset(settings, account, currency, page, adset_template, made.campaign) end},
      {:creative, fn _made -> Client.post(settings, "/#{account}/adcreatives", creative_params) end},
      {:ad, fn made -> ad(settings, account, name, made) end}
    ]

    case Enum.reduce_while(steps, {:ok, %{}}, &run_step/2) do
      {:ok, made} -> {:ok, done(account, made)}
      {:error, reason, made} -> {:error, undo(settings, reason, made)}
    end
  end

  defp adset(settings, account, currency, page, template, campaign_id) do
    with {:ok, params} <- MetaAdsBuild.adset(Map.put(template, "campaign_id", campaign_id), currency, {:ok, page}) do
      Client.post(settings, "/#{account}/adsets", params)
    end
  end

  defp ad(settings, account, name, made) do
    with {:ok, params} <- MetaAdsBuild.ad(%{"name" => name <> ": ad", "adset_id" => made.adset, "creative_id" => made.creative}) do
      Client.post(settings, "/#{account}/ads", params)
    end
  end

  defp run_step({step, fun}, {:ok, made}) do
    case fun.(made) do
      {:ok, %{"id" => id}} -> {:cont, {:ok, Map.put(made, step, id)}}
      {:ok, _} -> {:halt, {:error, "Meta did not give back an id for the #{step}.", made}}
      {:error, reason} -> {:halt, {:error, "Creating the #{step} failed: #{reason}", made}}
    end
  end

  # What was made before the failure is deleted.
  defp undo(settings, reason, made) do
    undone = for step <- [:ad, :adset, :campaign], id = made[step], do: {step, Client.post(settings, "/#{id}", status: "DELETED")}
    failed = for {step, {:error, _}} <- undone, do: step

    cond do
      made == %{} -> reason
      failed == [] -> reason <> " What had been created before was deleted, so nothing is left in the account."
      true -> reason <> " Some of what had been created could not be deleted (#{Enum.join(failed, ", ")}); check Ads Manager."
    end
  end

  defp done(account, made) do
    "Draft created, everything PAUSED (nothing is shown or spent yet).\n" <>
      "Campaign #{made.campaign}, ad set #{made.adset}, creative #{made.creative}, ad #{made.ad}.\n" <>
      "Review it with meta_ads_preview, and turn it on in Ads Manager: " <>
      "https://adsmanager.facebook.com/adsmanager/manage/campaigns?act=#{String.replace_prefix(account, "act_", "")}&selected_campaign_ids=#{made.campaign}"
  end
end
