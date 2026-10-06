# Meta Ads

Run Facebook and Instagram ads from a Pepe agent: read accounts, campaigns, ad sets, ads and results, research audiences, and build, edit, pause, duplicate and (if you allow it) turn on campaigns. It uses Meta's official Marketing API.

```bash
pepe plugin install @jhonathas/meta-ads
```

## Tools

**Reading (changes nothing)**

| Tool | Does |
|---|---|
| `meta_ads_accounts` | Lists your ad accounts with status, currency and total spend |
| `meta_ads_campaigns`, `meta_ads_adsets`, `meta_ads_ads` | List them with status, budget, targeting and, for ads, why Meta rejected one |
| `meta_ads_insights` | Results for a period: spend, reach, clicks, CTR, CPC, CPM, results per action, ROAS. By account, campaign, ad set or ad; broken down by age, gender, country, placement and more; by day, week or month |
| `meta_ads_get` | Everything about one campaign, ad set or ad |
| `meta_ads_search_targeting` | Finds interests, behaviors, places and more, with the ids to use in an ad set |
| `meta_ads_estimate` | Estimates how many people an audience reaches before you build it |
| `meta_ads_audiences`, `meta_ads_pixels`, `meta_ads_pages` | Custom audiences, pixels, Facebook Pages and linked Instagram accounts |
| `meta_ads_preview` | A link that shows how an ad looks |

**Creating (everything is made PAUSED)**

| Tool | Does |
|---|---|
| `meta_ads_create_draft` | The whole thing in one call: campaign, ad set, creative and ad, with a link to review it. If a step fails, what was made before it is deleted |
| `meta_ads_create_campaign`, `meta_ads_create_adset`, `meta_ads_create_creative`, `meta_ads_create_ad` | The same steps one by one, for full control (audience, placements, schedule, bidding, link, video, carousel or an existing post) |
| `meta_ads_upload_video` | Adds a video from a public `https://` address |
| `meta_ads_create_lookalike` | A lookalike audience from an existing one |

**Changing**

| Tool | Does |
|---|---|
| `meta_ads_update` | Renames, changes budgets, schedule, audience or the creative of an ad |
| `meta_ads_set_status` | Pauses, archives, deletes, or turns ON |
| `meta_ads_duplicate` | Copies a campaign, ad set or ad (the copy is PAUSED) |

## What you need

- A **Meta developer** account and an **app** (<https://developers.facebook.com>), with the **Marketing API** product.
- An **ad account**, and a **Facebook Page** the ads run as (and optionally the linked Instagram account).
- An **access token** with `ads_read` to read, plus `ads_management` to create or change. The most durable way is a **System User** in Business Manager, assigned the ad account and Page: its token does not expire. Meta's own documentation describes the steps; check them against the screens you see, since Meta changes them often.

## Set it up

In the Pepe dashboard open **Plugins**, find **meta-ads** and choose **Configure**:

| Field | What to put |
|---|---|
| Access token | Written as `${META_ADS_ACCESS_TOKEN}`, with the real value in the Pepe server's environment |
| Ad account id | The default account (digits). Optional |
| Facebook Page id | The Page the ads are published as. Needed to create ads |
| Instagram account id | Optional. To show the Instagram profile on the ads |
| Allow creating | `no` (the default) is read only. `yes` lets the agent create and change things, always PAUSED |
| Highest daily budget | The most a daily budget may be, in whole units like `50`. Required to write any budget. A lifetime budget may be at most this times its days |
| Allow turning on | `no` (the default): the agent can never start spending. `yes` lets it turn on things whose budgets are within the limit |
| Graph API version | Optional, like `v23.0` |

The same settings can come from the environment: `META_ADS_ACCESS_TOKEN`, `META_ADS_ACCOUNT_ID`, `META_ADS_MAX_DAILY_BUDGET`, and the others in the same style.

Then give the tools to an agent, reading first:

```bash
pepe agent tools my-agent --add meta_ads_accounts,meta_ads_campaigns,meta_ads_adsets,meta_ads_ads,meta_ads_insights
```

## Keep it safe (this plugin can spend real money)

- **Writing is off** until you set *Allow creating* to `yes`.
- **Everything the agent creates is PAUSED.** Nothing spends until something turns it on.
- **Turning on is a separate switch** (*Allow turning on*), and before any turn-on the plugin checks every budget involved (the ad, its ad set and its campaign) against *Highest daily budget*. Budgets above it are refused.
- A budget cannot be written at all without the limit set, and one above it is refused before any request.
- Every write asks for approval unless you pre-approve it. Do not pre-approve `meta_ads_set_status`.
- What comes back from Meta (names, ad text, feedback) is written by other people, so it reaches the model framed as quoted material, never as instructions.
- Some audiences are restricted by Meta (housing, employment, credit, politics). The agent must name the special ad category; it never guesses.
