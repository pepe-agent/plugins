# Meta Ads (Facebook and Instagram ads) tools for Pepe, as a drop-in plugin.
#
# This file holds the shared client and the tools that READ: accounts, campaigns, ad sets, ads, results
# with breakdowns, details of any object, targeting search, audience size estimates, audiences, pixels,
# Pages and Instagram accounts, and ad previews. meta-ads-create.exs holds what CREATES (always
# paused) and meta-ads-manage.exs what changes things (edit, pause, archive, duplicate, lookalikes,
# and turning on). Each tool is an ordinary Pepe tool, so an agent holds exactly the ones it is given,
# and every write still passes the permission gate.
#
# Settings come from the plugin's Configure dialog, falling back to environment variables:
#
#   * access_token     / META_ADS_ACCESS_TOKEN      a token with ads_read (and ads_management to write)
#   * ad_account_id    / META_ADS_ACCOUNT_ID        the ad account used when a call names none
#   * page_id          / META_ADS_PAGE_ID           the Facebook Page the ads are published as
#   * instagram_user_id / META_ADS_INSTAGRAM_USER_ID the Instagram account the ads run as (optional)
#   * writes           / META_ADS_WRITES            "yes" to let the agent create and change; else read only
#   * activate         / META_ADS_ACTIVATE          "yes" to let the agent also turn things ON (spends money)
#   * max_daily_budget / META_ADS_MAX_DAILY_BUDGET  the most a daily budget may be (whole units); writing budgets needs it
#   * api_version      / META_ADS_API_VERSION       the Graph API version, like v23.0
#
# META_ADS_API_URL overrides the address (for a proxy or a test); it is not a normal setting.

defmodule Pepe.Plugins.MetaAds.Client do
  @moduledoc """
  Settings, the Graph API calls, ids and money, and the targeting builder the tools share.
  """

  @default_version "v23.0"

  # Currencies Meta counts in whole units (no cents).
  @whole_unit ~w(CLP COP CRC HUF IDR ISK JPY KRW PYG TWD UGX VND XAF XOF XPF)

  # ---- settings ------------------------------------------------------------------------

  @doc "The connection settings, or `{:error, message}` naming what is missing."
  def settings do
    case setting("access_token", "META_ADS_ACCESS_TOKEN") do
      nil ->
        {:error, "Meta Ads is not configured. Set the access token under Plugins -> Configure (or the META_ADS_ACCESS_TOKEN env var)."}

      token ->
        base = (setting("api_url", "META_ADS_API_URL") || "https://graph.facebook.com") |> String.trim() |> String.trim_trailing("/")
        {:ok, %{base: base <> "/" <> (setting("api_version", "META_ADS_API_VERSION") || @default_version), token: token}}
    end
  end

  def setting(key, env_key), do: Pepe.Plugins.config("meta-ads", key) || env(env_key)

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  @doc "Creating and changing are off until the operator turns them on."
  def writable? do
    if yes?("writes", "META_ADS_WRITES"),
      do: :ok,
      else: {:error, "Writing to Meta Ads is off. Set \"Allow creating\" to yes under Plugins -> Configure."}
  end

  @doc "Turning things on (which starts spending) is off until the operator turns that on separately."
  def activation? do
    if yes?("activate", "META_ADS_ACTIVATE"),
      do: :ok,
      else:
        {:error,
         "Turning things on is off. Set \"Allow turning on\" to yes under Plugins -> Configure. Until then, a person turns a draft on in Ads Manager."}
  end

  defp yes?(key, env_key), do: setting(key, env_key) |> to_string() |> String.downcase() == "yes"

  @doc "A money amount as plain text with two decimals (never scientific notation)."
  def fmt(number), do: :erlang.float_to_binary(number * 1.0, decimals: 2)

  @doc "The ceiling for a daily budget, in whole units, or an error when none was set."
  def max_daily_budget do
    case Float.parse(to_string(setting("max_daily_budget", "META_ADS_MAX_DAILY_BUDGET") || "")) do
      {limit, _} when limit > 0 -> {:ok, limit}
      _ -> {:error, "Set the highest daily budget (\"Highest daily budget\") under Plugins -> Configure before writing budgets."}
    end
  end

  # ---- ids, dates, text ------------------------------------------------------------------

  @doc "The ad account a call is about: the one named, else the default, as `act_` and its digits."
  def account(value) do
    case (blank(value) || setting("ad_account_id", "META_ADS_ACCOUNT_ID"))
         |> to_string()
         |> String.trim()
         |> String.replace_prefix("act_", "") do
      "" ->
        {:error, "No ad account given and no default ad account is configured."}

      digits ->
        if Regex.match?(~r/\A\d+\z/, digits),
          do: {:ok, "act_" <> digits},
          else: {:error, "#{inspect(value)} is not an ad account id (digits, like 1234567890)."}
    end
  end

  @doc "A numeric id (campaign, ad set, ad, audience, pixel, page...)."
  def id(value, label \\ "id") do
    text = value |> to_string() |> String.trim()
    if Regex.match?(~r/\A\d+\z/, text), do: {:ok, text}, else: {:error, "#{inspect(value)} is not a valid #{label} (digits)."}
  end

  def optional_id(value, label) do
    case blank(value) do
      nil -> {:ok, nil}
      _ -> id(value, label)
    end
  end

  @doc "The Facebook Page the ads run as: the one named, else the default."
  def page_id(value) do
    case blank(value) || setting("page_id", "META_ADS_PAGE_ID") do
      nil -> {:error, "No Facebook Page given and no default Page is configured."}
      page -> id(page, "Facebook Page id")
    end
  end

  def instagram_user_id(value),
    do: optional_id(blank(value) || setting("instagram_user_id", "META_ADS_INSTAGRAM_USER_ID"), "Instagram account id")

  @doc "A date as Meta wants it (YYYY-MM-DD)."
  def date(value) do
    text = to_string(value)

    if Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, text) and match?({:ok, _}, Date.from_iso8601(text)),
      do: {:ok, text},
      else: {:error, "#{inspect(value)} is not a date (like 2026-10-31)."}
  end

  def optional_date(value) do
    case blank(value) do
      nil -> {:ok, nil}
      text -> date(text)
    end
  end

  @doc "An https address."
  def https(value, field) do
    if Regex.match?(~r{\Ahttps://[^\s]+\z}, to_string(value)), do: {:ok, value}, else: {:error, "`#{field}` must be an https address."}
  end

  def one_of(value, allowed, field) do
    if value in allowed, do: {:ok, value}, else: {:error, "`#{field}` must be one of: #{Enum.join(allowed, ", ")}."}
  end

  def blank(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  def blank(_value), do: nil

  def put(map, _key, nil), do: map
  def put(map, _key, []), do: map
  def put(map, key, value), do: Map.put(map, key, value)

  # ---- http ----------------------------------------------------------------------------

  def get(settings, path, params \\ []),
    do: handle(Req.get(settings.base <> path, params: [access_token: settings.token] ++ params, receive_timeout: 60_000, retry: false))

  def post(settings, path, params),
    do: handle(Req.post(settings.base <> path, form: [access_token: settings.token] ++ params, receive_timeout: 60_000, retry: false))

  defp handle({:ok, %{status: status, body: body}}) when status in 200..299, do: {:ok, body}
  defp handle({:ok, %{status: status, body: body}}), do: {:error, explain(status, body)}
  defp handle({:error, reason}), do: {:error, "Could not reach Meta: #{inspect(reason)}"}

  defp explain(_status, %{"error" => %{"code" => 190}}),
    do: "Meta did not accept the access token (it expired, was revoked, or the password changed). Create a new one."

  defp explain(_status, %{"error" => %{"code" => code}}) when code in [4, 17, 32, 613, 80_000, 80_003, 80_004],
    do: "Meta is rate limiting this account or app. Try again in a few minutes."

  defp explain(_status, %{"error" => %{"code" => code} = error}) when code in [10, 200, 294],
    do:
      "The token lacks a permission for this (reading needs ads_read, writing needs ads_management, and the ad account has to be assigned to it)#{detail(error)}"

  defp explain(status, %{"error" => error}), do: "Meta refused it (#{status})#{detail(error)}"
  defp explain(status, _body), do: "Meta answered with an error (#{status})."

  # Meta puts the useful reason in error_user_msg (and its title), not always in message.
  defp detail(error) do
    parts = [error["error_user_title"], error["error_user_msg"] || error["message"]] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    if parts == [], do: ".", else: ": " <> Enum.join(parts, ". ")
  end

  @doc "The currency of an ad account."
  def currency(settings, account) do
    case get(settings, "/#{account}", fields: "currency") do
      {:ok, %{"currency" => currency}} -> {:ok, currency}
      {:ok, _} -> {:error, "Meta did not say which currency this ad account uses."}
      error -> error
    end
  end

  # ---- money -----------------------------------------------------------------------------

  @doc "Whole units (like 30) to the smallest unit Meta takes in a write (like 3000)."
  def to_minor(amount, currency), do: if(currency in @whole_unit, do: round(amount), else: round(amount * 100))

  @doc "An amount the way account and budget fields hold it (the smallest unit) as `BRL 12.34`."
  def money_minor(nil, _currency), do: nil

  def money_minor(amount, currency) do
    case Integer.parse(to_string(amount)) do
      {units, ""} ->
        whole? = currency in @whole_unit
        "#{currency} #{:erlang.float_to_binary(if(whole?, do: units * 1.0, else: units / 100), decimals: if(whole?, do: 0, else: 2))}"

      _ ->
        nil
    end
  end

  @doc "An amount the way insights hold it (already in whole units) as `BRL 12.34`."
  def money(nil, _currency), do: nil

  def money(amount, currency) do
    case Float.parse(to_string(amount)) do
      {value, _} -> "#{currency} #{:erlang.float_to_binary(value, decimals: 2)}"
      :error -> nil
    end
  end

  def number(value) do
    case Float.parse(to_string(value)) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  def format(value), do: value |> number() |> :erlang.float_to_binary(decimals: 2)

  def sum(rows, key), do: Enum.reduce(rows, 0.0, &(&2 + number(&1[key])))

  # ---- targeting ----------------------------------------------------------------------------

  @platforms ~w(facebook instagram audience_network messenger)
  @position_keys %{
    "facebook_positions" => ~w(feed right_hand_column marketplace video_feeds story search instream_video facebook_reels profile_feed),
    "instagram_positions" => ~w(stream story explore explore_home reels profile_feed shop),
    "messenger_positions" => ~w(story sponsored_messages),
    "audience_network_positions" => ~w(classic rewarded_video)
  }

  @doc """
  The audience and placements of an ad set, from the tool's own arguments, as Meta's targeting
  object. Needs at least one place. Everything is checked here, so a mistake never reaches Meta.
  """
  def targeting(args) do
    with {:ok, geo} <- geo(args),
         {:ok, {age_min, age_max}} <- ages(args["age_min"], args["age_max"]),
         {:ok, gender} <- gender(args["gender"]),
         {:ok, interests} <- ids(args["interests"], "interest id"),
         {:ok, behaviors} <- ids(args["behaviors"], "behavior id"),
         {:ok, audiences} <- ids(args["custom_audiences"], "custom audience id"),
         {:ok, excluded} <- ids(args["excluded_custom_audiences"], "excluded audience id"),
         {:ok, locales} <- ids(args["locales"], "locale id"),
         {:ok, placements} <- placements(args["placements"]) do
      flexible = %{} |> put("interests", Enum.map(interests, &%{"id" => &1})) |> put("behaviors", Enum.map(behaviors, &%{"id" => &1}))

      spec =
        %{
          "geo_locations" => geo,
          "age_min" => age_min,
          "age_max" => age_max,
          # Meta asks every ad set to say whether it lets its automation widen the audience.
          "targeting_automation" => %{"advantage_audience" => if(args["advantage_audience"] == true, do: 1, else: 0)}
        }
        |> put("genders", gender)
        |> put("flexible_spec", if(flexible == %{}, do: [], else: [flexible]))
        |> put("custom_audiences", Enum.map(audiences, &%{"id" => &1}))
        |> put("excluded_custom_audiences", Enum.map(excluded, &%{"id" => &1}))
        |> put("locales", Enum.map(locales, &String.to_integer/1))
        |> Map.merge(placements)

      {:ok, spec}
    end
  end

  defp geo(args) do
    with {:ok, countries} <- countries(args["countries"]),
         {:ok, regions} <- ids(args["regions"], "region key"),
         {:ok, cities} <- cities(args["cities"]) do
      geo = %{} |> put("countries", countries) |> put("regions", Enum.map(regions, &%{"key" => &1})) |> put("cities", cities)
      if geo == %{}, do: {:error, "Give at least one place: `countries` (like [\"BR\"]), `regions` or `cities`."}, else: {:ok, geo}
    end
  end

  defp countries(nil), do: {:ok, []}

  defp countries(list) when is_list(list) and length(list) <= 50 do
    codes = Enum.map(list, &(&1 |> to_string() |> String.upcase()))

    if Enum.all?(codes, &Regex.match?(~r/\A[A-Z]{2}\z/, &1)),
      do: {:ok, codes},
      else: {:error, "`countries` must be two-letter codes, like [\"BR\"]."}
  end

  defp countries(_other), do: {:error, "`countries` must be a list of two-letter codes, like [\"BR\"]."}

  # A city is its key (from meta_ads_search_targeting), or {key, radius}; the radius is in kilometres.
  defp cities(nil), do: {:ok, []}

  defp cities(list) when is_list(list) and length(list) <= 50 do
    Enum.reduce_while(list, {:ok, []}, fn city, {:ok, acc} ->
      {key, radius} = if is_map(city), do: {city["key"], city["radius"]}, else: {city, nil}

      with {:ok, key} <- id(key, "city key"),
           true <- is_nil(radius) or (is_number(radius) and radius >= 17 and radius <= 80) do
        entry = %{"key" => key} |> then(&if(radius, do: Map.merge(&1, %{"radius" => radius, "distance_unit" => "kilometer"}), else: &1))
        {:cont, {:ok, acc ++ [entry]}}
      else
        false -> {:halt, {:error, "A city radius must be between 17 and 80 km."}}
        error -> {:halt, error}
      end
    end)
  end

  defp cities(_other), do: {:error, "`cities` must be a list of city keys."}

  defp ages(min, max) do
    min = if is_integer(min), do: min, else: 18
    max = if is_integer(max), do: max, else: 65

    if min in 18..65 and max in 18..65 and min <= max,
      do: {:ok, {min, max}},
      else: {:error, "Ages must be between 18 and 65, with age_min not above age_max."}
  end

  defp gender(value) when value in [nil, "all"], do: {:ok, []}
  defp gender("men"), do: {:ok, [1]}
  defp gender("women"), do: {:ok, [2]}
  defp gender(_other), do: {:error, "`gender` must be all, men or women."}

  defp ids(nil, _label), do: {:ok, []}

  defp ids(list, label) when is_list(list) and length(list) <= 100 do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case id(value, label) do
        {:ok, good} -> {:cont, {:ok, acc ++ [good]}}
        error -> {:halt, error}
      end
    end)
  end

  defp ids(_other, label), do: {:error, "Expected a list of #{label}s."}

  # "automatic" (or nothing) lets Meta place the ad where it performs; a map picks platforms and positions.
  defp placements(value) when value in [nil, "automatic"], do: {:ok, %{}}

  defp placements(%{"platforms" => platforms} = map) when is_list(platforms) and platforms != [] do
    with true <- Enum.all?(platforms, &(&1 in @platforms)),
         {:ok, positions} <- positions(map) do
      {:ok, Map.put(positions, "publisher_platforms", platforms)}
    else
      false -> {:error, "`placements.platforms` must be among: #{Enum.join(@platforms, ", ")}."}
      error -> error
    end
  end

  defp placements(_other), do: {:error, "`placements` must be \"automatic\" or {\"platforms\": [...], and optional *_positions lists}."}

  defp positions(map) do
    Enum.reduce_while(@position_keys, {:ok, %{}}, fn {key, allowed}, {:ok, acc} ->
      case map[key] do
        nil ->
          {:cont, {:ok, acc}}

        list when is_list(list) ->
          if Enum.all?(list, &(&1 in allowed)),
            do: {:cont, {:ok, Map.put(acc, key, list)}},
            else: {:halt, {:error, "`placements.#{key}` must be among: #{Enum.join(allowed, ", ")}."}}

        _ ->
          {:halt, {:error, "`placements.#{key}` must be a list."}}
      end
    end)
  end

  # ---- what comes back -------------------------------------------------------------------

  @doc """
  Text that came out of Meta (names, targeting labels, preview text) is written by whoever manages the
  account, so it reaches the model framed as quoted material, never as instructions.
  """
  def external(text), do: Pepe.Security.ExternalContent.mark_untrusted("meta-ads", Pepe.Security.ExternalContent.sanitize(text))

  @doc "A short text for a nested value (an audience, a promoted object) without losing what it says."
  def compact(nil), do: ""
  def compact(value) when is_binary(value), do: value
  def compact(value), do: Jason.encode!(value)
end

defmodule Pepe.Plugins.MetaAdsAccounts do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @statuses %{
    1 => "active",
    2 => "disabled",
    3 => "unsettled",
    7 => "in risk review",
    8 => "pending settlement",
    9 => "in grace period",
    100 => "pending closure",
    101 => "closed"
  }

  @impl true
  def name, do: "meta_ads_accounts"

  @impl true
  def spec do
    function(
      "meta_ads_accounts",
      "List the Meta ad accounts this token can see, with their ids, status, currency and what they have spent in total.",
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
         {:ok, body} <-
           Client.get(settings, "/me/adaccounts", fields: "name,account_id,account_status,currency,amount_spent,timezone_name", limit: 50) do
      case body["data"] do
        [_ | _] = accounts -> {:ok, accounts |> Enum.map_join("\n", &line/1) |> Client.external()}
        _ -> {:ok, "This token sees no ad accounts. The ad account has to be assigned to it."}
      end
    end
  end

  defp line(a) do
    spent = Client.money_minor(a["amount_spent"], a["currency"])

    "#{a["name"]} (act_#{a["account_id"]}, #{Map.get(@statuses, a["account_status"], "status #{a["account_status"]}")}, #{a["currency"]}#{if spent, do: ", spent in total " <> spent}, #{a["timezone_name"]})"
  end
end

defmodule Pepe.Plugins.MetaAdsList do
  @moduledoc false
  # The three lists (campaigns, ad sets, ads) differ only in what they ask for and how a line reads.
  alias Pepe.Plugins.MetaAds.Client

  @status_filters %{
    "active" => ["ACTIVE"],
    "paused" => ["PAUSED", "CAMPAIGN_PAUSED", "ADSET_PAUSED"],
    "problems" => ["DISAPPROVED", "WITH_ISSUES"],
    "archived" => ["ARCHIVED"]
  }

  def statuses, do: Map.keys(@status_filters) ++ ["all"]

  def run(args, edge, fields, line_fun, empty) do
    max = if is_integer(args["max"]), do: args["max"] |> min(50) |> max(1), else: 25

    with {:ok, account} <- Client.account(args["account"]),
         {:ok, parent} <- parent(args, account),
         {:ok, settings} <- Client.settings(),
         {:ok, currency} <- Client.currency(settings, account),
         {:ok, body} <- Client.get(settings, "/#{parent}/#{edge}", [fields: fields, limit: max] ++ filter(args["status"])) do
      case body["data"] do
        [_ | _] = rows -> {:ok, rows |> Enum.map_join("\n", &line_fun.(&1, currency)) |> Client.external()}
        _ -> {:ok, empty}
      end
    end
  end

  defp parent(args, account) do
    case Client.optional_id(args["campaign_id"], "campaign id") do
      {:ok, nil} -> {:ok, account}
      {:ok, campaign} -> {:ok, campaign}
      error -> error
    end
  end

  defp filter(status) when status in [nil, "active"], do: [effective_status: Jason.encode!(@status_filters["active"])]
  defp filter("all"), do: []
  defp filter(status), do: if(@status_filters[status], do: [effective_status: Jason.encode!(@status_filters[status])], else: [])

  def budget(row, currency) do
    cond do
      row["daily_budget"] -> ", daily budget " <> (Client.money_minor(row["daily_budget"], currency) || "?")
      row["lifetime_budget"] -> ", lifetime budget " <> (Client.money_minor(row["lifetime_budget"], currency) || "?")
      true -> ""
    end
  end
end

defmodule Pepe.Plugins.MetaAdsCampaigns do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAdsList

  @impl true
  def name, do: "meta_ads_campaigns"

  @impl true
  def spec do
    function("meta_ads_campaigns", "List the campaigns of a Meta ad account with their objective, status and budget.", %{
      "type" => "object",
      "properties" => %{
        "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."},
        "status" => %{"type" => "string", "enum" => MetaAdsList.statuses(), "description" => "Which campaigns (default active)."},
        "max" => %{"type" => "integer", "description" => "How many (1 to 50, default 25)."}
      }
    })
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    MetaAdsList.run(
      args,
      "campaigns",
      "name,effective_status,objective,daily_budget,lifetime_budget,bid_strategy,start_time,stop_time",
      &line/2,
      "No campaigns match."
    )
  end

  defp line(c, currency),
    do:
      "#{c["name"]} (id #{c["id"]}, #{c["effective_status"]}, #{c["objective"]}#{MetaAdsList.budget(c, currency)}#{if c["bid_strategy"], do: ", " <> c["bid_strategy"]})"
end

defmodule Pepe.Plugins.MetaAdsAdsets do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsList

  @impl true
  def name, do: "meta_ads_adsets"

  @impl true
  def spec do
    function(
      "meta_ads_adsets",
      "List the ad sets of an ad account, or of one campaign: status, budget, what they optimize for, schedule and audience.",
      %{
        "type" => "object",
        "properties" => %{
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."},
          "campaign_id" => %{"type" => "string", "description" => "Only the ad sets of this campaign (optional)."},
          "status" => %{"type" => "string", "enum" => MetaAdsList.statuses(), "description" => "Which ad sets (default active)."},
          "max" => %{"type" => "integer", "description" => "How many (1 to 50, default 25)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    fields =
      "name,campaign_id,effective_status,daily_budget,lifetime_budget,optimization_goal,billing_event,bid_strategy,start_time,end_time,destination_type,targeting"

    MetaAdsList.run(args, "adsets", fields, &line/2, "No ad sets match.")
  end

  defp line(s, currency) do
    t = s["targeting"] || %{}
    places = get_in(t, ["geo_locations", "countries"]) |> List.wrap() |> Enum.join(" ")
    ages = if t["age_min"], do: ", ages #{t["age_min"]}-#{t["age_max"]}", else: ""

    when_ =
      if s["start_time"],
        do: ", #{String.slice(s["start_time"], 0, 10)} to #{String.slice(to_string(s["end_time"] || "no end"), 0, 10)}",
        else: ""

    "#{s["name"]} (id #{s["id"]}, campaign #{s["campaign_id"]}, #{s["effective_status"]}#{MetaAdsList.budget(s, currency)}, #{s["optimization_goal"]}, #{Client.compact(s["destination_type"])}#{when_}, #{places}#{ages})"
  end
end

defmodule Pepe.Plugins.MetaAdsAds do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAdsList

  @impl true
  def name, do: "meta_ads_ads"

  @impl true
  def spec do
    function(
      "meta_ads_ads",
      "List the ads of an ad account, or of one campaign, with their status and any review problem. Status \"problems\" shows the rejected ones.",
      %{
        "type" => "object",
        "properties" => %{
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."},
          "campaign_id" => %{"type" => "string", "description" => "Only the ads of this campaign (optional)."},
          "status" => %{"type" => "string", "enum" => MetaAdsList.statuses(), "description" => "Which ads (default active)."},
          "max" => %{"type" => "integer", "description" => "How many (1 to 50, default 25)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    MetaAdsList.run(args, "ads", "name,adset_id,campaign_id,effective_status,creative{id},ad_review_feedback", &line/2, "No ads match.")
  end

  defp line(a, _currency) do
    problems =
      a
      |> get_in(["ad_review_feedback", "global"])
      |> then(fn x -> if is_map(x), do: Map.values(x), else: List.wrap(x) end)
      |> Enum.join("; ")

    "#{a["name"]} (id #{a["id"]}, ad set #{a["adset_id"]}, campaign #{a["campaign_id"]}, #{a["effective_status"]}, creative #{get_in(a, ["creative", "id"])}#{if problems != "", do: ", review: " <> problems})"
  end
end

defmodule Pepe.Plugins.MetaAdsInsights do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @periods ~w(today yesterday last_3d last_7d last_14d last_28d last_30d last_90d this_month last_month this_year maximum)
  @levels ~w(account campaign adset ad)
  @breakdowns ~w(age gender country region publisher_platform platform_position device_platform impression_device)
  @increments ~w(day week month)
  @fields "campaign_name,adset_name,ad_name,spend,impressions,reach,frequency,clicks,ctr,cpc,cpm,actions,action_values,cost_per_action_type,purchase_roas,account_currency"

  @impl true
  def name, do: "meta_ads_insights"

  @impl true
  def spec do
    function(
      "meta_ads_insights",
      "Results of Meta ads over a period: spend, impressions, reach, frequency, clicks, CTR, CPC and what the ads produced " <>
        "(clicks, leads, purchases, ROAS). For a whole account or one campaign, one row per campaign, ad set or ad, " <>
        "optionally split by age, gender, country, platform or day.",
      %{
        "type" => "object",
        "properties" => %{
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."},
          "object_id" => %{"type" => "string", "description" => "Only this campaign, ad set or ad (optional)."},
          "period" => %{
            "type" => "string",
            "enum" => @periods,
            "description" => "A named period (default last_7d). Ignored when since is given."
          },
          "since" => %{"type" => "string", "description" => "Start date, YYYY-MM-DD (with until)."},
          "until" => %{"type" => "string", "description" => "End date, YYYY-MM-DD (default today)."},
          "level" => %{
            "type" => "string",
            "enum" => @levels,
            "description" => "One row per account, campaign, adset or ad (default campaign)."
          },
          "breakdown" => %{"type" => "string", "enum" => @breakdowns, "description" => "Also split each row by this (optional)."},
          "by_time" => %{"type" => "string", "enum" => @increments, "description" => "Split by day, week or month (optional)."},
          "max" => %{"type" => "integer", "description" => "How many rows (1 to 100, default 25)."}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(100) |> max(1), else: 25
    level = if args["level"] in @levels, do: args["level"], else: "campaign"

    with {:ok, account} <- Client.account(args["account"]),
         {:ok, object} <- Client.optional_id(args["object_id"], "object id"),
         {:ok, period} <- period(args),
         {:ok, split} <- split(args),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <-
           Client.get(settings, "/#{object || account}/insights", [fields: @fields, level: level, limit: max] ++ period ++ split) do
      case body["data"] do
        [_ | _] = rows -> {:ok, rows |> render(level, args["breakdown"]) |> Client.external()}
        _ -> {:ok, "No results for that period."}
      end
    end
  end

  defp period(%{"since" => since} = args) when is_binary(since) and since != "" do
    with {:ok, from} <- Client.date(since),
         {:ok, to} <- Client.date(args["until"] || Date.to_iso8601(Date.utc_today())) do
      {:ok, [time_range: Jason.encode!(%{"since" => from, "until" => to})]}
    end
  end

  defp period(args), do: {:ok, [date_preset: if(args["period"] in @periods, do: args["period"], else: "last_7d")]}

  defp split(args) do
    with {:ok, breakdown} <- optional(args["breakdown"], @breakdowns, "breakdown"),
         {:ok, increment} <- optional(args["by_time"], @increments, "by_time") do
      {:ok,
       if(breakdown, do: [breakdowns: breakdown], else: []) ++
         if(increment, do: [time_increment: %{"day" => 1, "week" => 7, "month" => "monthly"}[increment]], else: [])}
    end
  end

  defp optional(nil, _allowed, _field), do: {:ok, nil}
  defp optional(value, allowed, field), do: Client.one_of(value, allowed, field)

  defp render(rows, level, breakdown) do
    lines = Enum.map(rows, &row(&1, level, breakdown))
    total = if length(rows) > 1, do: [total(rows)], else: []
    Enum.join(lines ++ total, "\n")
  end

  defp row(row, level, breakdown) do
    currency = row["account_currency"] || ""

    names =
      for {title, key} <- [{"Campaign", "campaign_name"}, {"Ad set", "adset_name"}, {"Ad", "ad_name"}],
          level != "account",
          row[key],
          do: "#{title}: #{row[key]}"

    label = if names == [], do: "Account", else: List.last(names)
    split = if breakdown && row[breakdown], do: " [#{breakdown} #{row[breakdown]}]", else: ""

    numbers =
      [
        "spend " <> (Client.money(row["spend"], currency) || "0"),
        "impressions #{row["impressions"] || 0}",
        "reach #{row["reach"] || 0}",
        row["frequency"] && "frequency #{Client.format(row["frequency"])}",
        "clicks #{row["clicks"] || 0}",
        row["ctr"] && "CTR #{Client.format(row["ctr"])}%",
        row["cpc"] && "CPC #{Client.format(row["cpc"])}",
        row["cpm"] && "CPM #{Client.format(row["cpm"])}"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    "#{label}#{split} (#{row["date_start"]} to #{row["date_stop"]})\n  #{numbers}#{results(row)}#{roas(row)}"
  end

  defp results(%{"actions" => [_ | _] = actions} = row) do
    costs = Map.new(List.wrap(row["cost_per_action_type"]), &{&1["action_type"], &1["value"]})

    top =
      actions
      |> Enum.sort_by(&(-Client.number(&1["value"])))
      |> Enum.take(4)
      |> Enum.map_join(", ", fn a ->
        "#{a["action_type"]} #{a["value"]}#{if costs[a["action_type"]], do: " (#{Client.format(costs[a["action_type"]])} each)"}"
      end)

    "\n  results: " <> top
  end

  defp results(_row), do: ""

  defp roas(%{"purchase_roas" => [%{"value" => value} | _]}), do: "\n  purchase ROAS: #{Client.format(value)}"
  defp roas(_row), do: ""

  defp total(rows) do
    currency = List.first(rows)["account_currency"] || ""

    "Total of these #{length(rows)}: spend #{Client.money(Client.sum(rows, "spend"), currency)}, impressions #{round(Client.sum(rows, "impressions"))}, clicks #{round(Client.sum(rows, "clicks"))}"
  end
end

defmodule Pepe.Plugins.MetaAdsGet do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @fields %{
    "campaign" =>
      "id,name,objective,effective_status,status,daily_budget,lifetime_budget,spend_cap,bid_strategy,buying_type,special_ad_categories,start_time,stop_time,created_time,updated_time",
    "adset" =>
      "id,name,campaign_id,effective_status,status,daily_budget,lifetime_budget,optimization_goal,billing_event,bid_strategy,bid_amount,destination_type,promoted_object,start_time,end_time,targeting,issues_info,created_time,updated_time",
    "ad" =>
      "id,name,adset_id,campaign_id,effective_status,status,creative{id,name},ad_review_feedback,issues_info,tracking_specs,created_time,updated_time",
    "creative" => "id,name,object_story_spec,object_story_id,url_tags,call_to_action_type,thumbnail_url,instagram_user_id,status"
  }

  @impl true
  def name, do: "meta_ads_get"

  @impl true
  def spec do
    function(
      "meta_ads_get",
      "Read everything about one campaign, ad set, ad or creative: its settings, budget, audience (targeting), schedule and problems.",
      %{
        "type" => "object",
        "properties" => %{
          "type" => %{"type" => "string", "enum" => Map.keys(@fields), "description" => "What kind of object it is."},
          "id" => %{"type" => "string", "description" => "Its id (digits)."}
        },
        "required" => ["type", "id"]
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"type" => type, "id" => id}, _ctx) do
    with {:ok, type} <- Client.one_of(type, Map.keys(@fields), "type"),
         {:ok, id} <- Client.id(id),
         {:ok, settings} <- Client.settings(),
         {:ok, object} <- Client.get(settings, "/#{id}", fields: @fields[type]) do
      {:ok, object |> Enum.sort() |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{Client.compact(value)}" end) |> Client.external()}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_get needs a `type` and an `id`."}
end

defmodule Pepe.Plugins.MetaAdsSearchTargeting do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @kinds ~w(interest behavior demographic location locale)

  @impl true
  def name, do: "meta_ads_search_targeting"

  @impl true
  def spec do
    function(
      "meta_ads_search_targeting",
      "Find the ids to target in an ad set: interests (like \"running\"), behaviors, demographics, places (cities and regions " <>
        "with their keys) and languages. Use the ids it gives in meta_ads_create_adset.",
      %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"type" => "string", "enum" => @kinds, "description" => "What to look for."},
          "query" => %{
            "type" => "string",
            "description" =>
              "Words to look for (for places, a name like \"Uberlandia\"; optional for behavior and demographic, which list their options)."
          },
          "country" => %{"type" => "string", "description" => "For places: limit to this two-letter country code (optional)."},
          "max" => %{"type" => "integer", "description" => "How many (1 to 30, default 15)."}
        },
        "required" => ["kind"]
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(%{"kind" => kind} = args, _ctx) do
    max = if is_integer(args["max"]), do: args["max"] |> min(30) |> max(1), else: 15
    query = Client.blank(args["query"])

    with {:ok, kind} <- Client.one_of(kind, @kinds, "kind"),
         {:ok, params} <- params(kind, query, args["country"]),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/search", params ++ [limit: max]) do
      case body["data"] do
        [_ | _] = found -> {:ok, found |> Enum.map_join("\n", &line(kind, &1)) |> Client.external()}
        _ -> {:ok, "Nothing found."}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_search_targeting needs a `kind`."}

  defp params("interest", nil, _country), do: {:error, "Give a `query` to search interests."}
  defp params("interest", query, _country), do: {:ok, [type: "adinterest", q: query]}

  defp params("behavior", query, _country),
    do: {:ok, [type: "adTargetingCategory", class: "behaviors"] ++ if(query, do: [q: query], else: [])}

  defp params("demographic", query, _country),
    do: {:ok, [type: "adTargetingCategory", class: "demographics"] ++ if(query, do: [q: query], else: [])}

  defp params("locale", query, _country), do: {:ok, [type: "adlocale"] ++ if(query, do: [q: query], else: [])}
  defp params("location", nil, _country), do: {:error, "Give a `query` (a place name) to search places."}

  defp params("location", query, country) do
    with {:ok, code} <- country(country) do
      {:ok,
       [type: "adgeolocation", q: query, location_types: Jason.encode!(["city", "region"])] ++ if(code, do: [country_code: code], else: [])}
    end
  end

  defp country(nil), do: {:ok, nil}

  defp country(code),
    do:
      if(Regex.match?(~r/\A[A-Za-z]{2}\z/, to_string(code)),
        do: {:ok, String.upcase(code)},
        else: {:error, "`country` must be a two-letter code."}
      )

  defp line("location", item), do: "#{item["type"]} #{item["name"]}#{region(item)}, #{item["country_name"]} (key #{item["key"]})"
  defp line(_kind, item), do: "#{item["name"]} (id #{item["id"]}#{size(item)}#{path(item)})"

  defp region(%{"region" => region}) when is_binary(region), do: ", " <> region
  defp region(_item), do: ""

  defp size(%{"audience_size_lower_bound" => low, "audience_size_upper_bound" => high}), do: ", audience #{low} to #{high}"
  defp size(_item), do: ""

  defp path(%{"path" => path}) when is_list(path), do: ", " <> Enum.join(path, " > ")
  defp path(_item), do: ""
end

defmodule Pepe.Plugins.MetaAdsEstimate do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @goals ~w(REACH IMPRESSIONS LINK_CLICKS LANDING_PAGE_VIEWS POST_ENGAGEMENT LEAD_GENERATION OFFSITE_CONVERSIONS CONVERSATIONS APP_INSTALLS THRUPLAY)

  @impl true
  def name, do: "meta_ads_estimate"

  @impl true
  def spec do
    function(
      "meta_ads_estimate",
      "Estimate how many people an audience reaches (daily and monthly) before spending anything. Takes the same audience " <>
        "arguments as meta_ads_create_adset.",
      %{
        "type" => "object",
        "properties" => %{
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."},
          "optimization_goal" => %{
            "type" => "string",
            "enum" => @goals,
            "description" => "What the ads would optimize for (default REACH)."
          },
          "countries" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Two-letter country codes."},
          "regions" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Region keys from meta_ads_search_targeting."
          },
          "cities" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "City keys from meta_ads_search_targeting."},
          "age_min" => %{"type" => "integer"},
          "age_max" => %{"type" => "integer"},
          "gender" => %{"type" => "string", "enum" => ["all", "men", "women"]},
          "interests" => %{"type" => "array", "items" => %{"type" => "string"}},
          "behaviors" => %{"type" => "array", "items" => %{"type" => "string"}},
          "custom_audiences" => %{"type" => "array", "items" => %{"type" => "string"}}
        }
      }
    )
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def run(args, _ctx) do
    with {:ok, account} <- Client.account(args["account"]),
         {:ok, goal} <- Client.one_of(args["optimization_goal"] || "REACH", @goals, "optimization_goal"),
         {:ok, spec} <- Client.targeting(args),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/#{account}/delivery_estimate", targeting_spec: Jason.encode!(spec), optimization_goal: goal) do
      case body["data"] do
        [estimate | _] -> {:ok, render(estimate)}
        _ -> {:ok, "Meta gave no estimate for that audience."}
      end
    end
  end

  defp render(e) do
    if e["estimate_ready"] == false do
      "Meta is still working out this estimate. Ask again in a moment."
    else
      "Estimated reach: #{e["estimate_mau_lower_bound"]} to #{e["estimate_mau_upper_bound"]} people a month, about #{e["estimate_dau"]} a day."
    end
  end
end

defmodule Pepe.Plugins.MetaAdsAudiences do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_audiences"

  @impl true
  def spec do
    function(
      "meta_ads_audiences",
      "List the custom and lookalike audiences of an ad account, with their size and whether they are ready to use.",
      %{
        "type" => "object",
        "properties" => %{"account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}}
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    with {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <-
           Client.get(settings, "/#{account}/customaudiences",
             fields: "name,subtype,approximate_count_lower_bound,approximate_count_upper_bound,delivery_status",
             limit: 50
           ) do
      case body["data"] do
        [_ | _] = audiences -> {:ok, audiences |> Enum.map_join("\n", &line/1) |> Client.external()}
        _ -> {:ok, "No custom audiences."}
      end
    end
  end

  defp line(a) do
    size =
      if a["approximate_count_lower_bound"],
        do: ", #{a["approximate_count_lower_bound"]} to #{a["approximate_count_upper_bound"]} people",
        else: ""

    "#{a["name"]} (id #{a["id"]}, #{a["subtype"]}#{size}#{if a["delivery_status"], do: ", " <> to_string(a["delivery_status"]["description"] || a["delivery_status"]["status"])})"
  end
end

defmodule Pepe.Plugins.MetaAdsPixels do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_pixels"

  @impl true
  def spec do
    function(
      "meta_ads_pixels",
      "List the Meta pixels of an ad account (needed for conversion and sales campaigns) and when each last received an event.",
      %{
        "type" => "object",
        "properties" => %{"account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}}
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    with {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/#{account}/adspixels", fields: "name,last_fired_time", limit: 50) do
      case body["data"] do
        [_ | _] = pixels ->
          {:ok,
           pixels
           |> Enum.map_join("\n", &"#{&1["name"]} (id #{&1["id"]}, last event #{&1["last_fired_time"] || "never"})")
           |> Client.external()}

        _ ->
          {:ok, "This ad account has no pixels."}
      end
    end
  end
end

defmodule Pepe.Plugins.MetaAdsPages do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_pages"

  @impl true
  def spec do
    function(
      "meta_ads_pages",
      "List the Facebook Pages the token can use for ads, and the Instagram accounts an ad account can run ads as. Gives the ids that creatives need.",
      %{
        "type" => "object",
        "properties" => %{"account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}}
      }
    )
  end

  @impl true
  def concurrent?, do: true
  @impl true
  def outside_content?, do: true

  @impl true
  def run(args, _ctx) do
    with {:ok, account} <- Client.account(args["account"]),
         {:ok, settings} <- Client.settings(),
         {:ok, pages} <- Client.get(settings, "/me/accounts", fields: "name,id", limit: 50),
         {:ok, instagram} <- Client.get(settings, "/#{account}/instagram_accounts", fields: "username,id", limit: 25) do
      page_lines = for p <- List.wrap(pages["data"]), do: "Page #{p["name"]} (id #{p["id"]})"
      ig_lines = for i <- List.wrap(instagram["data"]), do: "Instagram @#{i["username"]} (id #{i["id"]})"

      case page_lines ++ ig_lines do
        [] -> {:ok, "No Pages or Instagram accounts are available to this token."}
        lines -> {:ok, lines |> Enum.join("\n") |> Client.external()}
      end
    end
  end
end

defmodule Pepe.Plugins.MetaAdsPreview do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @formats ~w(MOBILE_FEED_STANDARD DESKTOP_FEED_STANDARD INSTAGRAM_STANDARD INSTAGRAM_STORY FACEBOOK_STORY_MOBILE)

  @impl true
  def name, do: "meta_ads_preview"

  @impl true
  def spec do
    function("meta_ads_preview", "Get a link that shows what an ad looks like in a placement, to review it before turning it on.", %{
      "type" => "object",
      "properties" => %{
        "ad_id" => %{"type" => "string", "description" => "The ad id (digits)."},
        "format" => %{"type" => "string", "enum" => @formats, "description" => "Where to show it (default MOBILE_FEED_STANDARD)."}
      },
      "required" => ["ad_id"]
    })
  end

  @impl true
  def concurrent?, do: true

  @impl true
  def run(%{"ad_id" => ad_id} = args, _ctx) do
    with {:ok, ad_id} <- Client.id(ad_id, "ad id"),
         {:ok, format} <- Client.one_of(args["format"] || "MOBILE_FEED_STANDARD", @formats, "format"),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <- Client.get(settings, "/#{ad_id}/previews", ad_format: format) do
      case body["data"] do
        [%{"body" => html} | _] -> link(html, format)
        _ -> {:ok, "Meta gave no preview for that ad."}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_preview needs an `ad_id`."}

  # The preview comes back as an iframe; its address is what a person opens.
  defp link(html, format) do
    case Regex.run(~r/src="([^"]+)"/, html) do
      [_, src] -> {:ok, "Preview (#{format}): " <> String.replace(src, "&amp;", "&")}
      _ -> {:ok, "Meta gave a preview, but no link could be read from it."}
    end
  end
end
