# Meta Ads: the tools that CHANGE what exists: edit, pause, archive, delete, duplicate, build a lookalike
# audience, and turn things on. Turning on is the one that starts spending, so it has its own switch
# in the settings and re-checks every budget against the operator's ceiling. See meta-ads-core.exs.

defmodule Pepe.Plugins.MetaAdsUpdate do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client
  alias Pepe.Plugins.MetaAdsBuild

  @types ~w(campaign adset ad)

  @impl true
  def name, do: "meta_ads_update"

  @impl true
  def spec do
    function(
      "meta_ads_update",
      "Change a campaign, ad set or ad: its name, budget, bid, schedule or (for an ad set) audience, or the creative of an ad. " <>
        "Only what you give is changed. Giving any audience field REPLACES the ad set's whole audience, so give all of it. " <>
        "This does not turn anything on or off; use meta_ads_set_status for that.",
      %{
        "type" => "object",
        "properties" => %{
          "type" => %{"type" => "string", "enum" => @types},
          "id" => %{"type" => "string", "description" => "Its id (digits)."},
          "name" => %{"type" => "string"},
          "daily_budget" => %{"type" => "number", "description" => "Campaign (shared budget) or ad set, in whole units."},
          "lifetime_budget" => %{"type" => "number", "description" => "Ad set only; needs end_date."},
          "spend_cap" => %{"type" => "number", "description" => "Campaign only, in whole units."},
          "bid_strategy" => %{"type" => "string", "enum" => MetaAdsBuild.bid_strategies()},
          "bid_amount" => %{"type" => "number", "description" => "Ad set only, for a bid cap or cost cap."},
          "start_date" => %{"type" => "string", "description" => "Ad set only, YYYY-MM-DD."},
          "end_date" => %{"type" => "string", "description" => "Ad set only, YYYY-MM-DD."},
          "creative_id" => %{"type" => "string", "description" => "Ad only: switch to this creative."},
          "countries" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Ad set audience (replaces it): countries."
          },
          "regions" => %{"type" => "array", "items" => %{"type" => "string"}},
          "cities" => %{"type" => "array"},
          "age_min" => %{"type" => "integer"},
          "age_max" => %{"type" => "integer"},
          "gender" => %{"type" => "string", "enum" => ["all", "men", "women"]},
          "interests" => %{"type" => "array", "items" => %{"type" => "string"}},
          "behaviors" => %{"type" => "array", "items" => %{"type" => "string"}},
          "custom_audiences" => %{"type" => "array", "items" => %{"type" => "string"}},
          "excluded_custom_audiences" => %{"type" => "array", "items" => %{"type" => "string"}},
          "placements" => %{"description" => "\"automatic\", or {platforms: [...], *_positions: [...]}."}
        },
        "required" => ["type", "id"]
      }
    )
  end

  @audience_keys ~w(countries regions cities interests behaviors custom_audiences excluded_custom_audiences placements)

  @impl true
  def run(%{"type" => type, "id" => id} = args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, type} <- Client.one_of(type, @types, "type"),
         {:ok, id} <- Client.id(id),
         {:ok, settings} <- Client.settings(),
         {:ok, currency} <- currency_of(settings, id),
         {:ok, params} <- changes(type, args, currency),
         {:ok, _} <- Client.post(settings, "/#{id}", params) do
      {:ok, "Updated #{type} #{id}: #{params |> Keyword.keys() |> Enum.join(", ")}."}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_update needs a `type` and an `id`."}

  # An object does not carry its currency; its ad account does.
  defp currency_of(settings, id) do
    with {:ok, %{"account_id" => account}} <- Client.get(settings, "/#{id}", fields: "account_id"),
         do: Client.currency(settings, "act_" <> to_string(account))
  end

  defp changes(type, args, currency) do
    with {:ok, start} <- Client.optional_date(args["start_date"]),
         {:ok, finish} <- Client.optional_date(args["end_date"]),
         {:ok, budget} <- MetaAdsBuild.budget(args["daily_budget"], args["lifetime_budget"], currency, start, finish),
         {:ok, targeting} <- audience(type, args),
         {:ok, rest} <- plain(type, args, currency, start, finish) do
      case budget ++ targeting ++ rest do
        [] -> {:error, "Nothing to change: give at least one field."}
        params -> {:ok, params}
      end
    end
  end

  defp audience("adset", args) do
    if Enum.any?(@audience_keys, &Map.has_key?(args, &1)) do
      with {:ok, spec} <- Client.targeting(args), do: {:ok, [targeting: Jason.encode!(spec)]}
    else
      {:ok, []}
    end
  end

  defp audience(_type, _args), do: {:ok, []}

  defp plain(type, args, currency, start, finish) do
    with {:ok, strategy} <- optional(args["bid_strategy"], MetaAdsBuild.bid_strategies(), "bid_strategy"),
         {:ok, creative} <- Client.optional_id(args["creative_id"], "creative id"),
         {:ok, spend} <- spend(args["spend_cap"], currency),
         {:ok, bid} <- bid(args["bid_amount"], currency) do
      allowed = %{
        "campaign" => [:name, :spend_cap, :bid_strategy],
        "adset" => [:name, :bid_amount, :bid_strategy, :start_time, :end_time],
        "ad" => [:name, :creative]
      }

      [
        name: Client.blank(args["name"]),
        spend_cap: spend,
        bid_strategy: strategy,
        bid_amount: bid,
        start_time: start,
        end_time: finish,
        creative: creative && Jason.encode!(%{"creative_id" => creative})
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> check_allowed(type, allowed[type])
    end
  end

  defp check_allowed(params, type, allowed) do
    case Enum.reject(Keyword.keys(params), &(&1 in allowed)) do
      [] -> {:ok, params}
      wrong -> {:error, "A #{type} cannot take #{wrong |> Enum.map(&to_string/1) |> Enum.join(", ")}."}
    end
  end

  defp optional(nil, _allowed, _field), do: {:ok, nil}
  defp optional(value, allowed, field), do: Client.one_of(value, allowed, field)

  defp spend(nil, _currency), do: {:ok, nil}
  defp spend(amount, currency) when is_number(amount) and amount > 0, do: {:ok, Client.to_minor(amount, currency)}
  defp spend(_other, _currency), do: {:error, "`spend_cap` must be a number above zero."}

  defp bid(nil, _currency), do: {:ok, nil}
  defp bid(amount, currency) when is_number(amount) and amount > 0, do: {:ok, Client.to_minor(amount, currency)}
  defp bid(_other, _currency), do: {:error, "`bid_amount` must be a number above zero."}
end

defmodule Pepe.Plugins.MetaAdsSetStatus do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @statuses ~w(PAUSED ARCHIVED DELETED ACTIVE)
  @types ~w(campaign adset ad)

  # Meta refuses a field the kind of object does not have, so each kind asks only for its own.
  @own %{
    "campaign" => "account_id,daily_budget,lifetime_budget,start_time,stop_time",
    "adset" => "account_id,campaign_id,daily_budget,lifetime_budget,start_time,end_time",
    "ad" => "account_id,adset_id,campaign_id"
  }
  @budget_fields "daily_budget,lifetime_budget,start_time,end_time"
  @campaign_budget_fields "daily_budget,lifetime_budget,start_time,stop_time"

  @impl true
  def name, do: "meta_ads_set_status"

  @impl true
  def spec do
    function(
      "meta_ads_set_status",
      "Pause, archive, delete or TURN ON a campaign, ad set or ad. ACTIVE starts delivery and SPENDS MONEY: it is refused unless the operator " <>
        "allowed turning things on, and unless every budget involved is within the operator's ceiling. DELETED cannot be undone.",
      %{
        "type" => "object",
        "properties" => %{
          "type" => %{"type" => "string", "enum" => @types},
          "id" => %{"type" => "string", "description" => "The campaign, ad set or ad id (digits)."},
          "status" => %{"type" => "string", "enum" => @statuses}
        },
        "required" => ["type", "id", "status"]
      }
    )
  end

  @impl true
  def run(%{"type" => type, "id" => id, "status" => status}, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, type} <- Client.one_of(type, @types, "type"),
         {:ok, status} <- Client.one_of(status, @statuses, "status"),
         {:ok, id} <- Client.id(id),
         {:ok, settings} <- Client.settings(),
         :ok <- gate(settings, type, id, status),
         {:ok, _} <- Client.post(settings, "/#{id}", status: status) do
      {:ok, message(id, status)}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_set_status needs a `type`, an `id` and a `status`."}

  # Pausing, archiving and deleting only need writing to be on. Turning on needs its own switch and
  # every budget it would spend from to be inside the ceiling.
  defp gate(_settings, _type, _id, status) when status != "ACTIVE", do: :ok

  defp gate(settings, type, id, "ACTIVE") do
    with :ok <- Client.activation?(),
         {:ok, cap} <- Client.max_daily_budget(),
         {:ok, object} <- Client.get(settings, "/#{id}", fields: @own[type]),
         {:ok, currency} <- Client.currency(settings, "act_" <> to_string(object["account_id"])),
         {:ok, rows} <- budgets(settings, type, id, object) do
      Enum.reduce_while(rows, :ok, fn row, :ok ->
        case within(row, currency, cap) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  # The object itself, what it spends from above it, and (for a campaign) what is inside it.
  defp budgets(settings, "campaign", id, object) do
    with {:ok, body} <- Client.get(settings, "/#{id}/adsets", fields: @budget_fields, limit: 100),
         do: {:ok, [object | List.wrap(body["data"])]}
  end

  defp budgets(settings, "adset", _id, object) do
    with {:ok, campaign} <- Client.get(settings, "/#{object["campaign_id"]}", fields: @campaign_budget_fields),
         do: {:ok, [object, campaign]}
  end

  defp budgets(settings, "ad", _id, object) do
    with {:ok, adset} <- Client.get(settings, "/#{object["adset_id"]}", fields: @budget_fields),
         {:ok, campaign} <- Client.get(settings, "/#{object["campaign_id"]}", fields: @campaign_budget_fields) do
      {:ok, [adset, campaign]}
    end
  end

  defp within(row, currency, cap) do
    cond do
      row["daily_budget"] -> daily(row["daily_budget"], currency, cap)
      row["lifetime_budget"] -> lifetime(row, currency, cap)
      true -> :ok
    end
  end

  defp daily(minor, currency, cap) do
    amount = amount(minor, currency)

    if amount <= cap,
      do: :ok,
      else:
        {:error,
         "Refused: a daily budget of #{Client.fmt(amount)} #{currency} is above the highest allowed (#{Client.fmt(cap)}). Lower it first (meta_ads_update), or have the operator raise the limit."}
  end

  defp lifetime(row, currency, cap) do
    finish = row["end_time"] || row["stop_time"]

    with true <- is_binary(finish),
         {:ok, to, _} <- DateTime.from_iso8601(finish),
         days = max(1, Date.diff(DateTime.to_date(to), parse_start(row["start_time"])) + 1),
         true <- amount(row["lifetime_budget"], currency) <= cap * days do
      :ok
    else
      false ->
        {:error,
         "Refused: a lifetime budget of #{Client.fmt(amount(row["lifetime_budget"], currency))} #{currency} is above what the highest daily budget (#{Client.fmt(cap)}) allows over its dates."}

      _ ->
        {:error, "Refused: a lifetime budget needs an end date to be checked against the highest daily budget."}
    end
  end

  defp parse_start(nil), do: Date.utc_today()

  defp parse_start(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _} -> DateTime.to_date(at)
      _ -> Date.utc_today()
    end
  end

  defp amount(minor, currency) do
    {units, _} = Integer.parse(to_string(minor))
    if currency in ~w(CLP COP CRC HUF IDR ISK JPY KRW PYG TWD UGX VND XAF XOF XPF), do: units * 1.0, else: units / 100
  end

  defp message(id, "ACTIVE"), do: "Turned ON #{id}. It can now be shown and it spends from its budget."
  defp message(id, "PAUSED"), do: "Paused #{id}."
  defp message(id, "ARCHIVED"), do: "Archived #{id}."
  defp message(id, "DELETED"), do: "Deleted #{id}. This cannot be undone."
end

defmodule Pepe.Plugins.MetaAdsDuplicate do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_duplicate"

  @impl true
  def spec do
    function(
      "meta_ads_duplicate",
      "Copy a campaign, ad set or ad. The copy is PAUSED, with its name suffixed \" copy\". A campaign or ad set is copied with everything inside it unless deep is false.",
      %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "description" => "What to copy (digits)."},
          "deep" => %{"type" => "boolean", "description" => "Copy what is inside too (default true)."},
          "into_campaign_id" => %{
            "type" => "string",
            "description" => "For an ad set or ad: the campaign or ad set to put the copy in (optional)."
          }
        },
        "required" => ["id"]
      }
    )
  end

  @impl true
  def run(%{"id" => id} = args, _ctx) do
    with :ok <- Client.writable?(),
         {:ok, id} <- Client.id(id),
         {:ok, into} <- Client.optional_id(args["into_campaign_id"], "target id"),
         {:ok, settings} <- Client.settings(),
         {:ok, body} <-
           Client.post(
             settings,
             "/#{id}/copies",
             [deep_copy: args["deep"] != false, status_option: "PAUSED", rename_options: Jason.encode!(%{"rename_suffix" => " copy"})] ++
               if(into, do: [campaign_id: into], else: [])
           ) do
      {:ok, "Copied #{id}, the copy is PAUSED: #{Jason.encode!(body)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_duplicate needs an `id`."}
end

defmodule Pepe.Plugins.MetaAdsCreateLookalike do
  @behaviour Pepe.Tools.Tool

  import Pepe.Tools.Tool, only: [function: 3]
  alias Pepe.Plugins.MetaAds.Client

  @impl true
  def name, do: "meta_ads_create_lookalike"

  @impl true
  def spec do
    function(
      "meta_ads_create_lookalike",
      "Create a lookalike audience: people similar to an existing custom audience, in one country. It takes Meta a few hours to fill.",
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "source_audience_id" => %{"type" => "string", "description" => "The custom audience to resemble (from meta_ads_audiences)."},
          "country" => %{"type" => "string", "description" => "Two-letter country code."},
          "percent" => %{"type" => "number", "description" => "How wide: 1 (most similar) to 20 (default 1) percent of the country."},
          "account" => %{"type" => "string", "description" => "The ad account id (optional if a default is set)."}
        },
        "required" => ["name", "source_audience_id", "country"]
      }
    )
  end

  @impl true
  def run(%{"name" => name, "source_audience_id" => source, "country" => country} = args, _ctx) when is_binary(name) and name != "" do
    percent = if is_number(args["percent"]), do: args["percent"], else: 1

    with :ok <- Client.writable?(),
         {:ok, account} <- Client.account(args["account"]),
         {:ok, source} <- Client.id(source, "audience id"),
         {:ok, country} <- country(country),
         true <- (percent >= 1 and percent <= 20) || {:error, "`percent` must be between 1 and 20."},
         {:ok, settings} <- Client.settings(),
         spec = Jason.encode!(%{"type" => "similarity", "country" => country, "ratio" => percent / 100}),
         {:ok, %{"id" => id}} <-
           Client.post(settings, "/#{account}/customaudiences",
             name: name,
             subtype: "LOOKALIKE",
             origin_audience_id: source,
             lookalike_spec: spec
           ) do
      {:ok, "Lookalike audience created: #{id}. Meta needs a few hours to fill it before it can be used."}
    end
  end

  def run(_args, _ctx), do: {:error, "meta_ads_create_lookalike needs a `name`, a `source_audience_id` and a `country`."}

  defp country(code),
    do:
      if(Regex.match?(~r/\A[A-Za-z]{2}\z/, to_string(code)),
        do: {:ok, String.upcase(code)},
        else: {:error, "`country` must be a two-letter code."}
      )
end
