defmodule Pepe.Plugins.MetaAdsTest do
  @moduledoc """
  The Meta Ads plugin against a fake Graph API: what each tool asks for and sends, how it reads the
  answers, and above all what it refuses to do (writing while off, spending past the ceiling, turning
  things on without the second switch) before any request is made. Nothing here talks to Meta.
  """
  use ExUnit.Case, async: false

  alias Pepe.Plugins.MetaAds.Client

  defp run(tool, args), do: apply(Module.concat([Pepe.Plugins, tool]), :run, [args, %{}])

  defmodule FakeGraph do
    @moduledoc false
    import Plug.Conn

    def init(test), do: test

    def call(conn, test) do
      conn = fetch_query_params(conn)
      {:ok, raw, conn} = read_body(conn)
      form = if raw == "", do: %{}, else: URI.decode_query(raw)
      params = Map.merge(conn.query_params, form)
      send(test, {:request, conn.method, String.replace_prefix(conn.request_path, "/v23.0", ""), params})
      scenario = Application.get_env(:pepe_plugins, :fake_meta, %{})
      route(conn, conn.method, String.replace_prefix(conn.request_path, "/v23.0", ""), params, scenario)
    end

    # ---- reads
    defp route(conn, "GET", "/me/adaccounts", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "name" => "Caren Ads",
              "account_id" => "123",
              "account_status" => 1,
              "currency" => "BRL",
              "amount_spent" => "1234500",
              "timezone_name" => "America/Sao_Paulo"
            }
          ]
        })

    defp route(conn, "GET", "/act_123", %{"fields" => "currency"}, s), do: json(conn, 200, %{"currency" => s[:currency] || "BRL"})

    defp route(conn, "GET", "/act_123/campaigns", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "id" => "555",
              "name" => "Launch",
              "effective_status" => "ACTIVE",
              "objective" => "OUTCOME_TRAFFIC",
              "daily_budget" => "5000",
              "bid_strategy" => "LOWEST_COST_WITHOUT_CAP"
            }
          ]
        })

    defp route(conn, "GET", "/act_123/adsets", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "id" => "666",
              "name" => "Brazil 25-45",
              "campaign_id" => "555",
              "effective_status" => "ACTIVE",
              "daily_budget" => "5000",
              "optimization_goal" => "LINK_CLICKS",
              "destination_type" => "WEBSITE",
              "start_time" => "2026-10-10T00:00:00-0300",
              "targeting" => %{"geo_locations" => %{"countries" => ["BR"]}, "age_min" => 25, "age_max" => 45}
            }
          ]
        })

    defp route(conn, "GET", "/act_123/ads", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "id" => "901",
              "name" => "Ad 1",
              "adset_id" => "666",
              "campaign_id" => "555",
              "effective_status" => "DISAPPROVED",
              "creative" => %{"id" => "cr9"},
              "ad_review_feedback" => %{"global" => %{"Policy" => "Text has too many words"}}
            }
          ]
        })

    defp route(conn, "GET", "/555/adsets", %{"fields" => f}, s) when f != "currency" do
      if s[:adsets],
        do: json(conn, 200, %{"data" => s[:adsets]}),
        else:
          json(conn, 200, %{
            "data" => [%{"id" => "666", "name" => "x", "campaign_id" => "555", "effective_status" => "PAUSED", "daily_budget" => "5000"}]
          })
    end

    defp route(conn, "GET", "/act_123/insights", _p, _s), do: insights(conn)
    defp route(conn, "GET", "/555/insights", _p, _s), do: insights(conn)

    defp route(conn, "GET", "/555", %{"fields" => f}, s) do
      cond do
        f =~ "account_id" ->
          json(
            conn,
            200,
            Map.merge(
              %{"account_id" => "123", "start_time" => "2026-10-10T00:00:00-0300", "stop_time" => "2026-10-20T00:00:00-0300"},
              s[:campaign] || %{}
            )
          )

        true ->
          json(conn, 200, %{
            "id" => "555",
            "name" => "Launch",
            "objective" => "OUTCOME_TRAFFIC",
            "effective_status" => "ACTIVE",
            "special_ad_categories" => []
          })
      end
    end

    defp route(conn, "GET", "/666", %{"fields" => f}, s) do
      if f =~ "account_id" or f =~ "campaign_id",
        do:
          json(
            conn,
            200,
            Map.merge(
              %{"account_id" => "123", "campaign_id" => "555", "daily_budget" => "5000", "start_time" => "2026-10-10T00:00:00-0300"},
              s[:adset] || %{}
            )
          ),
        else: json(conn, 200, Map.merge(%{"daily_budget" => "5000", "start_time" => "2026-10-10T00:00:00-0300"}, s[:adset] || %{}))
    end

    defp route(conn, "GET", "/901", %{"fields" => f}, _s) when f == "account_id", do: json(conn, 200, %{"account_id" => "123"})

    defp route(conn, "GET", "/901", %{"fields" => f}, _s) when f != "account_id",
      do: json(conn, 200, %{"account_id" => "123", "adset_id" => "666", "campaign_id" => "555"})

    defp route(conn, "GET", "/search", %{"type" => "adinterest"}, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "id" => "6003139266461",
              "name" => "Running",
              "audience_size_lower_bound" => 100_000,
              "audience_size_upper_bound" => 200_000,
              "path" => ["Interests", "Sports"]
            }
          ]
        })

    defp route(conn, "GET", "/search", %{"type" => "adgeolocation"}, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{"key" => "2421836", "name" => "Uberlandia", "type" => "city", "region" => "Minas Gerais", "country_name" => "Brazil"}
          ]
        })

    defp route(conn, "GET", "/search", _p, _s), do: json(conn, 200, %{"data" => [%{"id" => "1", "name" => "Frequent travelers"}]})

    defp route(conn, "GET", "/act_123/delivery_estimate", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "estimate_ready" => true,
              "estimate_dau" => 5000,
              "estimate_mau_lower_bound" => 100_000,
              "estimate_mau_upper_bound" => 150_000
            }
          ]
        })

    defp route(conn, "GET", "/act_123/customaudiences", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{
              "id" => "70",
              "name" => "Site visitors",
              "subtype" => "WEBSITE",
              "approximate_count_lower_bound" => 1000,
              "approximate_count_upper_bound" => 1500,
              "delivery_status" => %{"description" => "Ready"}
            }
          ]
        })

    defp route(conn, "GET", "/act_123/adspixels", _p, _s),
      do: json(conn, 200, %{"data" => [%{"id" => "80", "name" => "Site pixel", "last_fired_time" => "2026-10-05T10:00:00+0000"}]})

    defp route(conn, "GET", "/me/accounts", _p, _s), do: json(conn, 200, %{"data" => [%{"id" => "11", "name" => "Caren"}]})

    defp route(conn, "GET", "/act_123/instagram_accounts", _p, _s),
      do: json(conn, 200, %{"data" => [%{"id" => "22", "username" => "caren.app"}]})

    defp route(conn, "GET", "/901/previews", _p, _s),
      do:
        json(conn, 200, %{
          "data" => [
            %{"body" => ~s(<iframe src="https://www.facebook.com/ads/api/preview_iframe.php?d=abc&amp;t=xyz" width="320"></iframe>)}
          ]
        })

    # ---- writes
    defp route(conn, "POST", "/act_123/campaigns", %{"name" => "BAD"}, _s),
      do:
        json(conn, 400, %{
          "error" => %{
            "code" => 100,
            "message" => "Invalid parameter",
            "error_user_title" => "Campaign name rejected",
            "error_user_msg" => "The name is not allowed."
          }
        })

    defp route(conn, "POST", "/act_123/campaigns", _p, _s), do: json(conn, 200, %{"id" => "1001"})

    defp route(conn, "POST", "/act_123/adsets", %{"name" => "FAIL" <> _}, _s),
      do: json(conn, 400, %{"error" => %{"code" => 100, "message" => "bad", "error_user_msg" => "Ad set refused."}})

    defp route(conn, "POST", "/act_123/adsets", _p, _s), do: json(conn, 200, %{"id" => "1002"})
    defp route(conn, "POST", "/act_123/adcreatives", _p, _s), do: json(conn, 200, %{"id" => "1003"})
    defp route(conn, "POST", "/act_123/ads", _p, _s), do: json(conn, 200, %{"id" => "1004"})
    defp route(conn, "POST", "/act_123/advideos", _p, _s), do: json(conn, 200, %{"id" => "1005"})
    defp route(conn, "POST", "/act_123/customaudiences", _p, _s), do: json(conn, 200, %{"id" => "aud1"})

    defp route(conn, "POST", "/" <> id, _p, _s) when id in ["555/copies", "666/copies"],
      do: json(conn, 200, %{"copied_campaign_id" => "999"})

    defp route(conn, "POST", "/" <> _id, _p, _s), do: json(conn, 200, %{"success" => true})

    defp route(conn, _m, _path, _p, _s), do: json(conn, 400, %{"error" => %{"code" => 190, "message" => "Invalid OAuth access token."}})

    defp insights(conn) do
      json(conn, 200, %{
        "data" => [
          %{
            "campaign_name" => "Launch",
            "date_start" => "2026-10-01",
            "date_stop" => "2026-10-07",
            "account_currency" => "BRL",
            "spend" => "120.50",
            "impressions" => "10234",
            "reach" => "8000",
            "frequency" => "1.28",
            "clicks" => "230",
            "ctr" => "2.2475",
            "cpc" => "0.5239",
            "cpm" => "11.77",
            "actions" => [%{"action_type" => "link_click", "value" => "230"}, %{"action_type" => "landing_page_view", "value" => "180"}],
            "cost_per_action_type" => [%{"action_type" => "link_click", "value" => "0.52"}],
            "purchase_roas" => [%{"action_type" => "omni_purchase", "value" => "3.4"}],
            "age" => "25-34"
          },
          %{
            "campaign_name" => "Brand",
            "date_start" => "2026-10-01",
            "date_stop" => "2026-10-07",
            "account_currency" => "BRL",
            "spend" => "30.00",
            "impressions" => "5000",
            "clicks" => "40",
            "age" => "35-44"
          }
        ]
      })
    end

    defp json(conn, status, data), do: conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: {FakeGraph, self()}, port: 0, startup_log: false)
    {:ok, {_addr, port}} = ThousandIsland.listener_info(server)
    Application.put_env(:pepe_plugins, :fake_meta, %{})

    config(%{
      "access_token" => "tok",
      "api_url" => "http://127.0.0.1:#{port}",
      "ad_account_id" => "123",
      "page_id" => "11",
      "writes" => "yes",
      "max_daily_budget" => "50"
    })

    on_exit(fn ->
      Application.delete_env(:pepe_plugins, :plugin_config)
      Application.delete_env(:pepe_plugins, :fake_meta)
    end)

    :ok
  end

  defp config(map), do: Application.put_env(:pepe_plugins, :plugin_config, %{"meta-ads" => map})

  defp change(key, value),
    do:
      Application.put_env(
        :pepe_plugins,
        :plugin_config,
        update_in(Application.get_env(:pepe_plugins, :plugin_config), ["meta-ads"], &Map.put(&1, key, value))
      )

  defp drop(key),
    do:
      Application.put_env(
        :pepe_plugins,
        :plugin_config,
        update_in(Application.get_env(:pepe_plugins, :plugin_config), ["meta-ads"], &Map.delete(&1, key))
      )

  defp scenario(map), do: Application.put_env(:pepe_plugins, :fake_meta, map)

  defp posts do
    receive do
      {:request, "POST", path, params} -> [{path, params} | posts()]
    after
      50 -> []
    end
  end

  describe "reading" do
    test "accounts show their status, currency and total spend in money" do
      assert {:ok, out} = run(:MetaAdsAccounts, %{})
      assert out =~ "Caren Ads (act_123, active, BRL, spent in total BRL 12345.00, America/Sao_Paulo)"
      assert_received {:request, "GET", "/me/adaccounts", %{"access_token" => "tok"}}
    end

    test "campaigns, ad sets and ads are listed with budgets, targeting and review problems" do
      assert {:ok, campaigns} = run(:MetaAdsCampaigns, %{"status" => "paused"})
      assert campaigns =~ "Launch (id 555, ACTIVE, OUTCOME_TRAFFIC, daily budget BRL 50.00, LOWEST_COST_WITHOUT_CAP)"
      assert_received {:request, "GET", "/act_123/campaigns", %{"effective_status" => status}}
      assert status =~ "CAMPAIGN_PAUSED"

      assert {:ok, adsets} = run(:MetaAdsAdsets, %{"campaign_id" => "555", "status" => "all"})
      assert adsets =~ "x (id 666"
      assert_received {:request, "GET", "/555/adsets", params}
      refute Map.has_key?(params, "effective_status")

      assert {:ok, adsets_account} = run(:MetaAdsAdsets, %{})
      assert adsets_account =~ "LINK_CLICKS, WEBSITE, 2026-10-10 to no end, BR, ages 25-45"

      assert {:ok, ads} = run(:MetaAdsAds, %{"status" => "problems"})
      assert ads =~ "DISAPPROVED, creative cr9, review: Text has too many words"
    end

    test "insights send the period, level, breakdown and time split, and read spend, results and ROAS" do
      assert {:ok, out} = run(:MetaAdsInsights, %{"period" => "last_30d", "level" => "campaign", "breakdown" => "age", "by_time" => "day"})
      assert_received {:request, "GET", "/act_123/insights", params}
      assert params["date_preset"] == "last_30d"
      assert params["level"] == "campaign"
      assert params["breakdowns"] == "age"
      assert params["time_increment"] == "1"

      assert out =~ "Campaign: Launch [age 25-34] (2026-10-01 to 2026-10-07)"
      assert out =~ "spend BRL 120.50, impressions 10234, reach 8000, frequency 1.28, clicks 230, CTR 2.25%, CPC 0.52, CPM 11.77"
      assert out =~ "results: link_click 230 (0.52 each), landing_page_view 180"
      assert out =~ "purchase ROAS: 3.40"
      assert out =~ "Total of these 2: spend BRL 150.50, impressions 15234, clicks 270"
    end

    test "insights take a date range, or one object, and refuse nonsense before asking" do
      assert {:ok, _} = run(:MetaAdsInsights, %{"since" => "2026-10-01", "until" => "2026-10-07", "object_id" => "555"})
      assert_received {:request, "GET", "/555/insights", %{"time_range" => range}}
      assert Jason.decode!(range) == %{"since" => "2026-10-01", "until" => "2026-10-07"}

      assert {:error, _} = run(:MetaAdsInsights, %{"since" => "yesterday"})
      assert {:error, _} = run(:MetaAdsInsights, %{"breakdown" => "mood"})
      assert {:error, _} = run(:MetaAdsInsights, %{"object_id" => "5; drop"})
      refute_received {:request, "GET", "/act_123/insights", _}
    end

    test "get asks only for the fields of that kind of object" do
      assert {:ok, out} = run(:MetaAdsGet, %{"type" => "campaign", "id" => "555"})
      assert out =~ "objective: OUTCOME_TRAFFIC"
      assert_received {:request, "GET", "/555", %{"fields" => fields}}
      assert fields =~ "spend_cap"
      refute fields =~ "adset_id"
      assert {:error, _} = run(:MetaAdsGet, %{"type" => "galaxy", "id" => "1"})
    end

    test "targeting search finds interests and places with their ids and keys" do
      assert {:ok, interests} = run(:MetaAdsSearchTargeting, %{"kind" => "interest", "query" => "running"})
      assert interests =~ "Running (id 6003139266461, audience 100000 to 200000, Interests > Sports)"
      assert_received {:request, "GET", "/search", %{"type" => "adinterest", "q" => "running"}}

      assert {:ok, places} = run(:MetaAdsSearchTargeting, %{"kind" => "location", "query" => "Uberlandia", "country" => "br"})
      assert places =~ "city Uberlandia, Minas Gerais, Brazil (key 2421836)"
      assert_received {:request, "GET", "/search", %{"type" => "adgeolocation", "country_code" => "BR"}}

      assert {:error, _} = run(:MetaAdsSearchTargeting, %{"kind" => "interest"})
    end

    test "an audience is sized from the same audience arguments an ad set takes" do
      assert {:ok, out} =
               run(:MetaAdsEstimate, %{
                 "countries" => ["br"],
                 "age_min" => 25,
                 "age_max" => 45,
                 "gender" => "women",
                 "interests" => ["6003139266461"]
               })

      assert out == "Estimated reach: 100000 to 150000 people a month, about 5000 a day."

      assert_received {:request, "GET", "/act_123/delivery_estimate", %{"targeting_spec" => spec, "optimization_goal" => "REACH"}}
      spec = Jason.decode!(spec)
      assert spec["geo_locations"] == %{"countries" => ["BR"]}
      assert spec["genders"] == [2]
      assert spec["flexible_spec"] == [%{"interests" => [%{"id" => "6003139266461"}]}]
      assert spec["targeting_automation"] == %{"advantage_audience" => 0}
    end

    test "audiences, pixels, pages and a preview link" do
      assert {:ok, audiences} = run(:MetaAdsAudiences, %{})
      assert audiences =~ "Site visitors (id 70, WEBSITE, 1000 to 1500 people, Ready)"
      assert {:ok, pixels} = run(:MetaAdsPixels, %{})
      assert pixels =~ "Site pixel (id 80, last event 2026-10-05"
      assert {:ok, pages} = run(:MetaAdsPages, %{})
      assert pages =~ "Page Caren (id 11)"
      assert pages =~ "Instagram @caren.app (id 22)"
      assert {:ok, preview} = run(:MetaAdsPreview, %{"ad_id" => "901"})
      assert preview == "Preview (MOBILE_FEED_STANDARD): https://www.facebook.com/ads/api/preview_iframe.php?d=abc&t=xyz"
    end

    test "everything read is framed as external content, never as instructions" do
      outputs =
        for {tool, args} <- [{:MetaAdsAccounts, %{}}, {:MetaAdsCampaigns, %{}}, {:MetaAdsInsights, %{}}, {:MetaAdsAudiences, %{}}],
            do: elem(run(tool, args), 1)

      for out <- outputs, do: assert(out =~ "BEGIN UNTRUSTED EXTERNAL CONTENT (source: meta-ads")

      for tool <-
            ~w(MetaAdsAccounts MetaAdsCampaigns MetaAdsAdsets MetaAdsAds MetaAdsInsights MetaAdsGet MetaAdsSearchTargeting MetaAdsAudiences MetaAdsPixels MetaAdsPages)a,
          do: assert(apply(Module.concat([Pepe.Plugins, tool]), :outside_content?, []))
    end
  end

  describe "writing is off until it is turned on" do
    test "every create and change is refused before any request, and reading still works" do
      change("writes", "no")

      calls = [
        {:MetaAdsCreateCampaign, %{"name" => "x", "objective" => "traffic", "special_ad_category" => "none"}},
        {:MetaAdsCreateAdset, %{"campaign_id" => "1", "name" => "x", "optimization_goal" => "REACH", "countries" => ["BR"]}},
        {:MetaAdsUploadVideo, %{"video_url" => "https://cdn.test/a.mp4"}},
        {:MetaAdsCreateCreative, %{"name" => "x"}},
        {:MetaAdsCreateAd, %{"name" => "x", "adset_id" => "1", "creative_id" => "2"}},
        {:MetaAdsCreateDraft, %{"name" => "x"}},
        {:MetaAdsUpdate, %{"type" => "campaign", "id" => "555", "name" => "y"}},
        {:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "PAUSED"}},
        {:MetaAdsDuplicate, %{"id" => "555"}},
        {:MetaAdsCreateLookalike, %{"name" => "x", "source_audience_id" => "70", "country" => "BR"}}
      ]

      for {tool, args} <- calls do
        assert {:error, msg} = run(tool, args)
        assert msg =~ "Writing to Meta Ads is off"
      end

      refute_received {:request, _, _, _}
      assert {:ok, _} = run(:MetaAdsAccounts, %{})
    end
  end

  describe "creating a campaign" do
    test "it is PAUSED, names its objective and special ad category, and needs no budget of its own" do
      assert {:ok, out} = run(:MetaAdsCreateCampaign, %{"name" => "Launch", "objective" => "sales", "special_ad_category" => "housing"})
      assert out =~ "Campaign created, PAUSED: 1001"

      assert [{"/act_123/campaigns", params}] = posts()
      assert params["status"] == "PAUSED"
      assert params["objective"] == "OUTCOME_SALES"
      assert params["special_ad_categories"] == ~s(["HOUSING"])
      refute Map.has_key?(params, "daily_budget")
    end

    test "a shared budget is in the smallest unit, kept under the ceiling, and a spend cap is converted" do
      assert {:ok, _} =
               run(:MetaAdsCreateCampaign, %{
                 "name" => "x",
                 "objective" => "traffic",
                 "special_ad_category" => "none",
                 "daily_budget" => 30,
                 "spend_cap" => 900
               })

      assert [{_, params}] = posts()
      assert params["daily_budget"] == "3000"
      assert params["spend_cap"] == "90000"
      assert params["bid_strategy"] == "LOWEST_COST_WITHOUT_CAP"

      assert {:error, msg} =
               run(:MetaAdsCreateCampaign, %{"name" => "x", "objective" => "traffic", "special_ad_category" => "none", "daily_budget" => 51})

      assert msg =~ "above the highest allowed (50.00)"
      assert posts() == []
    end

    test "the special ad category is required, never guessed, and Meta's own reason is passed on" do
      assert {:error, msg} = run(:MetaAdsCreateCampaign, %{"name" => "x", "objective" => "traffic"})
      assert msg =~ "special_ad_category"
      assert {:error, bad} = run(:MetaAdsCreateCampaign, %{"name" => "BAD", "objective" => "traffic", "special_ad_category" => "none"})
      assert bad =~ "Campaign name rejected. The name is not allowed."
    end

    test "writing a budget needs the operator's ceiling" do
      drop("max_daily_budget")

      assert {:error, msg} =
               run(:MetaAdsCreateCampaign, %{"name" => "x", "objective" => "traffic", "special_ad_category" => "none", "daily_budget" => 10})

      assert msg =~ "Highest daily budget"
    end
  end

  describe "creating an ad set" do
    @adset %{"campaign_id" => "555", "name" => "Set", "optimization_goal" => "LINK_CLICKS", "daily_budget" => 30, "countries" => ["br"]}

    test "audience, placements, schedule, bid and budget all reach Meta in its own format" do
      args =
        Map.merge(@adset, %{
          "destination_type" => "WEBSITE",
          "start_date" => "2026-10-10",
          "end_date" => "2026-10-20",
          "age_min" => 25,
          "age_max" => 45,
          "gender" => "women",
          "cities" => [%{"key" => "2421836", "radius" => 20}],
          "interests" => ["6003139266461"],
          "custom_audiences" => ["70"],
          "excluded_custom_audiences" => ["71"],
          "placements" => %{"platforms" => ["facebook", "instagram"], "instagram_positions" => ["stream", "reels"]},
          "bid_strategy" => "COST_CAP",
          "bid_amount" => 4.5
        })

      assert {:ok, out} = run(:MetaAdsCreateAdset, args)
      assert out =~ "Ad set created, PAUSED: 1002"

      assert [{"/act_123/adsets", p}] = posts()
      assert p["status"] == "PAUSED"
      assert p["campaign_id"] == "555"
      assert p["daily_budget"] == "3000"
      assert p["bid_strategy"] == "COST_CAP"
      assert p["bid_amount"] == "450"
      assert p["destination_type"] == "WEBSITE"
      assert p["start_time"] == "2026-10-10" and p["end_time"] == "2026-10-20"

      t = Jason.decode!(p["targeting"])

      assert t["geo_locations"] == %{
               "countries" => ["BR"],
               "cities" => [%{"key" => "2421836", "radius" => 20, "distance_unit" => "kilometer"}]
             }

      assert t["genders"] == [2] and t["age_min"] == 25
      assert t["custom_audiences"] == [%{"id" => "70"}] and t["excluded_custom_audiences"] == [%{"id" => "71"}]
      assert t["publisher_platforms"] == ["facebook", "instagram"] and t["instagram_positions"] == ["stream", "reels"]
    end

    test "a conversion goal names the pixel and the event; a lead goal uses the configured Page" do
      assert {:error, msg} = run(:MetaAdsCreateAdset, Map.put(@adset, "optimization_goal", "OFFSITE_CONVERSIONS"))
      assert msg =~ "pixel_id"

      assert {:ok, _} =
               run(
                 :MetaAdsCreateAdset,
                 Map.merge(@adset, %{"optimization_goal" => "OFFSITE_CONVERSIONS", "pixel_id" => "80", "custom_event_type" => "PURCHASE"})
               )

      assert [{_, sales}] = posts()
      assert Jason.decode!(sales["promoted_object"]) == %{"pixel_id" => "80", "custom_event_type" => "PURCHASE"}

      assert {:ok, _} = run(:MetaAdsCreateAdset, Map.put(@adset, "optimization_goal", "LEAD_GENERATION"))
      assert [{_, leads}] = posts()
      assert Jason.decode!(leads["promoted_object"]) == %{"page_id" => "11"}
    end

    test "a lifetime budget needs an end date and stays within the ceiling times the days" do
      base = Map.delete(@adset, "daily_budget")
      assert {:error, no_end} = run(:MetaAdsCreateAdset, Map.put(base, "lifetime_budget", 100))
      assert no_end =~ "needs an `end_date`"

      ten_days = Map.merge(base, %{"start_date" => "2026-10-10", "end_date" => "2026-10-19"})
      assert {:ok, _} = run(:MetaAdsCreateAdset, Map.put(ten_days, "lifetime_budget", 500))
      assert {:error, over} = run(:MetaAdsCreateAdset, Map.put(ten_days, "lifetime_budget", 501))
      assert over =~ "above the highest allowed"
      assert {:error, _} = run(:MetaAdsCreateAdset, Map.put(@adset, "lifetime_budget", 100))
    end

    test "a mistake is caught before the first request" do
      cases = [
        Map.put(@adset, "countries", ["Brazil"]),
        Map.delete(@adset, "countries"),
        Map.put(@adset, "daily_budget", 51),
        Map.put(@adset, "age_min", 12),
        Map.put(@adset, "optimization_goal", "WORLD_PEACE"),
        Map.put(@adset, "interests", ["running; drop"]),
        Map.put(@adset, "placements", %{"platforms" => ["myspace"]}),
        Map.put(@adset, "bid_strategy", "COST_CAP"),
        Map.merge(@adset, %{"start_date" => "2026-10-20", "end_date" => "2026-10-10"}),
        Map.put(@adset, "cities", [%{"key" => "1", "radius" => 5}])
      ]

      for args <- cases, do: assert({:error, _} = run(:MetaAdsCreateAdset, args))
      refute_received {:request, "POST", _, _}
    end

    test "Meta's own reason reaches the agent when it refuses an ad set" do
      assert {:error, msg} = run(:MetaAdsCreateAdset, Map.put(@adset, "name", "FAIL one"))
      assert msg =~ "Ad set refused."
    end
  end

  describe "creatives and ads" do
    test "a link creative carries the picture, the button, tracking and the Instagram account" do
      change("instagram_user_id", "22")

      args = %{
        "name" => "Link",
        "link" => "https://caren.app",
        "message" => "Hello",
        "headline" => "Try it",
        "image_url" => "https://cdn.test/a.jpg",
        "call_to_action" => "SIGN_UP",
        "url_tags" => "utm_source=meta&utm_medium=paid"
      }

      assert {:ok, "Creative created: 1003" <> _} = run(:MetaAdsCreateCreative, args)

      assert [{"/act_123/adcreatives", p}] = posts()
      assert p["instagram_user_id"] == "22"
      assert p["url_tags"] == "utm_source=meta&utm_medium=paid"
      data = Jason.decode!(p["object_story_spec"])
      assert data["page_id"] == "11"

      assert data["link_data"] == %{
               "link" => "https://caren.app",
               "message" => "Hello",
               "name" => "Try it",
               "picture" => "https://cdn.test/a.jpg",
               "call_to_action" => %{"type" => "SIGN_UP", "value" => %{"link" => "https://caren.app"}}
             }
    end

    test "video, carousel and post creatives each take their own shape" do
      assert {:ok, _} =
               run(:MetaAdsCreateCreative, %{
                 "name" => "V",
                 "kind" => "video",
                 "video_id" => "55",
                 "link" => "https://caren.app",
                 "message" => "Watch",
                 "headline" => "Hi",
                 "image_url" => "https://cdn.test/t.jpg"
               })

      assert [{_, video}] = posts()

      assert %{"video_data" => %{"video_id" => "55", "title" => "Hi", "image_url" => "https://cdn.test/t.jpg"}} =
               Jason.decode!(video["object_story_spec"])

      cards = [
        %{"link" => "https://caren.app/1", "image_url" => "https://cdn.test/1.jpg", "headline" => "One"},
        %{"link" => "https://caren.app/2", "image_url" => "https://cdn.test/2.jpg"}
      ]

      assert {:ok, _} =
               run(:MetaAdsCreateCreative, %{
                 "name" => "C",
                 "kind" => "carousel",
                 "link" => "https://caren.app",
                 "message" => "See",
                 "cards" => cards
               })

      assert [{_, carousel}] = posts()

      assert %{"link_data" => %{"child_attachments" => [%{"name" => "One"}, %{"link" => "https://caren.app/2"}]}} =
               Jason.decode!(carousel["object_story_spec"])

      assert {:ok, _} = run(:MetaAdsCreateCreative, %{"name" => "P", "kind" => "post", "facebook_post_id" => "11_9876"})
      assert [{_, post}] = posts()
      assert post["object_story_id"] == "11_9876"
      assert {:ok, _} = run(:MetaAdsCreateCreative, %{"name" => "IG", "kind" => "post", "instagram_media_id" => "1789"})
      assert [{_, ig}] = posts()
      assert ig["source_instagram_media_id"] == "1789"
    end

    test "bad creatives never reach Meta" do
      link = %{"name" => "x", "link" => "https://caren.app", "message" => "m"}

      cases = [
        Map.put(link, "link", "http://caren.app"),
        Map.delete(link, "message"),
        Map.put(link, "call_to_action", "BUY_NOW_OR_ELSE"),
        Map.put(link, "url_tags", "a b; c"),
        Map.put(link, "image_url", "ftp://x/y.jpg"),
        %{
          "name" => "x",
          "kind" => "carousel",
          "link" => "https://caren.app",
          "message" => "m",
          "cards" => [%{"link" => "https://caren.app"}]
        },
        %{"name" => "x", "kind" => "post", "facebook_post_id" => "not-a-post"},
        %{"name" => "x", "kind" => "post"},
        %{"name" => "x", "kind" => "video", "video_id" => "v", "link" => "https://caren.app", "message" => "m"} |> Map.delete("video_id")
      ]

      for args <- cases, do: assert({:error, _} = run(:MetaAdsCreateCreative, args))
      refute_received {:request, _, _, _}
    end

    test "an ad is created PAUSED from a creative, and a video is added by address" do
      assert {:ok, out} =
               run(
                 :MetaAdsCreateAd,
                 %{"name" => "Ad", "adset_id" => "s1", "creative_id" => "cr1"} |> Map.merge(%{"adset_id" => "666", "creative_id" => "77"})
               )

      assert out =~ "Ad created, PAUSED: 1004"
      assert [{"/act_123/ads", p}] = posts()
      assert p["status"] == "PAUSED" and p["adset_id"] == "666" and p["creative"] == ~s({"creative_id":"77"})

      assert {:ok, video} = run(:MetaAdsUploadVideo, %{"video_url" => "https://cdn.test/a.mp4", "name" => "Promo"})
      assert video =~ "Video added: 1005"
      assert [{"/act_123/advideos", v}] = posts()
      assert v["file_url"] == "https://cdn.test/a.mp4"
      assert {:error, _} = run(:MetaAdsUploadVideo, %{"video_url" => "http://x/a.mp4"})
    end
  end

  describe "the one-call draft" do
    @draft %{
      "name" => "Launch",
      "objective" => "traffic",
      "special_ad_category" => "none",
      "daily_budget" => 30,
      "countries" => ["BR"],
      "link" => "https://caren.app",
      "message" => "Hi",
      "image_url" => "https://cdn.test/a.jpg"
    }

    test "builds the campaign, ad set, creative and ad in order, all PAUSED, with a link to review" do
      assert {:ok, out} = run(:MetaAdsCreateDraft, @draft)
      assert out =~ "everything PAUSED"
      assert out =~ "Campaign 1001, ad set 1002, creative 1003, ad 1004"
      assert out =~ "adsmanager.facebook.com/adsmanager/manage/campaigns?act=123&selected_campaign_ids=1001"

      assert [{"/act_123/campaigns", campaign}, {"/act_123/adsets", adset}, {"/act_123/adcreatives", _}, {"/act_123/ads", ad}] = posts()
      assert campaign["status"] == "PAUSED" and adset["status"] == "PAUSED" and ad["status"] == "PAUSED"
      assert campaign["objective"] == "OUTCOME_TRAFFIC"

      assert adset["campaign_id"] == "1001" and adset["optimization_goal"] == "LINK_CLICKS" and adset["destination_type"] == "WEBSITE" and
               adset["daily_budget"] == "3000"

      assert ad["adset_id"] == "1002" and ad["creative"] == ~s({"creative_id":"1003"})
    end

    test "a sales draft counts purchases on the pixel" do
      assert {:ok, _} = run(:MetaAdsCreateDraft, Map.merge(@draft, %{"objective" => "sales", "pixel_id" => "80"}))
      assert [_, {"/act_123/adsets", adset}, _, _] = posts()
      assert adset["optimization_goal"] == "OFFSITE_CONVERSIONS"
      assert Jason.decode!(adset["promoted_object"]) == %{"pixel_id" => "80", "custom_event_type" => "PURCHASE"}
      assert {:error, msg} = run(:MetaAdsCreateDraft, Map.merge(@draft, %{"objective" => "sales"}))
      assert msg =~ "pixel_id"
    end

    test "a mistake in any part is caught before anything is created" do
      for args <- [
            Map.put(@draft, "daily_budget", 51),
            Map.put(@draft, "countries", ["nope"]),
            Map.delete(@draft, "special_ad_category"),
            Map.put(@draft, "link", "http://x"),
            Map.put(@draft, "objective", "world peace")
          ] do
        assert {:error, _} = run(:MetaAdsCreateDraft, args)
      end

      refute_received {:request, "POST", _, _}
    end

    test "if a step fails, what was made before it is deleted and the agent is told so" do
      assert {:error, msg} = run(:MetaAdsCreateDraft, Map.put(@draft, "name", "FAIL draft"))
      assert msg =~ "Creating the adset failed"
      assert msg =~ "Ad set refused."
      assert msg =~ "was deleted, so nothing is left"

      assert [{"/act_123/campaigns", _}, {"/act_123/adsets", _}, {"/1001", %{"status" => "DELETED"}}] = posts()
    end
  end

  describe "changing what exists" do
    test "an ad set's budget is converted and checked, its audience is replaced whole, and an empty change is refused" do
      assert {:ok, out} = run(:MetaAdsUpdate, %{"type" => "adset", "id" => "666", "name" => "New name", "daily_budget" => 40})
      assert out =~ "Updated adset 666: daily_budget, name"
      assert [{"/666", p}] = posts()
      assert p["daily_budget"] == "4000" and p["name"] == "New name"

      assert {:ok, _} = run(:MetaAdsUpdate, %{"type" => "adset", "id" => "666", "countries" => ["BR"], "age_min" => 30})
      assert [{"/666", t}] = posts()
      assert %{"geo_locations" => %{"countries" => ["BR"]}, "age_min" => 30} = Jason.decode!(t["targeting"])

      assert {:error, none} = run(:MetaAdsUpdate, %{"type" => "adset", "id" => "666"})
      assert none =~ "Nothing to change"
      assert {:error, high} = run(:MetaAdsUpdate, %{"type" => "adset", "id" => "666", "daily_budget" => 99})
      assert high =~ "above the highest allowed"
      assert posts() == []
    end

    test "a field the kind of object cannot take is refused, and an ad can switch creative" do
      assert {:error, msg} = run(:MetaAdsUpdate, %{"type" => "campaign", "id" => "555", "creative_id" => "77"})
      assert msg =~ "cannot take creative"
      assert {:error, _} = run(:MetaAdsUpdate, %{"type" => "ad", "id" => "901", "bid_amount" => 2})
      assert {:ok, _} = run(:MetaAdsUpdate, %{"type" => "ad", "id" => "901", "creative_id" => "77"})
      assert [{"/901", p}] = posts()
      assert p["creative"] == ~s({"creative_id":"77"})
    end

    test "pausing, archiving and deleting need only writing to be on" do
      for status <- ~w(PAUSED ARCHIVED DELETED) do
        assert {:ok, _} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => status})
        assert [{"/555", %{"status" => ^status}}] = posts()
      end
    end

    test "turning on is refused unless the operator allowed it, however small the budget" do
      assert {:error, msg} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
      assert msg =~ "Turning things on is off"
      assert posts() == []
    end

    test "with turning on allowed, every budget involved is checked against the ceiling first" do
      change("activate", "yes")

      assert {:ok, out} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
      assert out =~ "Turned ON 555"
      assert [{"/555", %{"status" => "ACTIVE"}}] = posts()

      scenario(%{adsets: [%{"id" => "666", "daily_budget" => "9000", "start_time" => "2026-10-10T00:00:00-0300"}]})
      assert {:error, over} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
      assert over =~ "daily budget of 90.00 BRL is above the highest allowed (50.00)"
      assert posts() == []
    end

    test "an ad's ad set and campaign are checked too, and a lifetime budget is judged over its dates" do
      change("activate", "yes")
      scenario(%{adset: %{"daily_budget" => "9000"}})
      assert {:error, _} = run(:MetaAdsSetStatus, %{"type" => "ad", "id" => "901", "status" => "ACTIVE"})
      assert {:error, _} = run(:MetaAdsSetStatus, %{"type" => "adset", "id" => "666", "status" => "ACTIVE"})

      scenario(%{adset: %{"daily_budget" => nil}, campaign: %{"lifetime_budget" => "200000"}})
      assert {:error, over} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
      assert over =~ "lifetime budget of 2000.00 BRL is above"

      scenario(%{campaign: %{"lifetime_budget" => "40000"}})
      assert {:ok, _} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
    end

    test "turning on needs the ceiling to be set at all" do
      change("activate", "yes")
      drop("max_daily_budget")
      assert {:error, msg} = run(:MetaAdsSetStatus, %{"type" => "campaign", "id" => "555", "status" => "ACTIVE"})
      assert msg =~ "Highest daily budget"
    end

    test "a copy is PAUSED and renamed, and a lookalike names its source, country and width" do
      assert {:ok, out} = run(:MetaAdsDuplicate, %{"id" => "555"})
      assert out =~ "the copy is PAUSED"
      assert [{"/555/copies", p}] = posts()
      assert p["status_option"] == "PAUSED" and p["deep_copy"] == "true" and p["rename_options"] == ~s({"rename_suffix":" copy"})

      assert {:ok, _} = run(:MetaAdsCreateLookalike, %{"name" => "Look", "source_audience_id" => "70", "country" => "br", "percent" => 2})
      assert [{"/act_123/customaudiences", l}] = posts()
      assert l["subtype"] == "LOOKALIKE" and l["origin_audience_id"] == "70"
      assert Jason.decode!(l["lookalike_spec"]) == %{"type" => "similarity", "country" => "BR", "ratio" => 0.02}

      assert {:error, _} =
               run(:MetaAdsCreateLookalike, %{"name" => "Look", "source_audience_id" => "70", "country" => "br", "percent" => 40})
    end
  end

  describe "when Meta says no" do
    test "an expired token says to create a new one" do
      change(
        "api_url",
        elem(:inet.parse_address(~c"127.0.0.1"), 0)
        |> then(fn _ -> Application.get_env(:pepe_plugins, :plugin_config)["meta-ads"]["api_url"] end)
      )

      Application.put_env(
        :pepe_plugins,
        :plugin_config,
        update_in(Application.get_env(:pepe_plugins, :plugin_config), ["meta-ads"], &Map.put(&1, "ad_account_id", "999"))
      )

      assert {:error, msg} = run(:MetaAdsCampaigns, %{})
      assert msg =~ "did not accept the access token"
    end

    test "settings that are missing or malformed say what to fix" do
      assert {:error, bad} = run(:MetaAdsCampaigns, %{"account" => "abc"})
      assert bad =~ "not an ad account id"
      Application.delete_env(:pepe_plugins, :plugin_config)
      assert {:error, msg} = Client.settings()
      assert msg =~ "Meta Ads is not configured"
    end
  end
end
