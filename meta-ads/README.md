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

## What you need before starting

- A **Meta Business portfolio** (Business Manager, <https://business.facebook.com>) that owns, or has access to, your **ad account** and your **Facebook Page**. The ad account needs a working payment method before anything can run.
- A **Meta developer** account (<https://developers.facebook.com>) and an **app** there.
- Optional: the **Instagram** account linked to the Page, if the ads should also run as that profile.

## Set it up (about 20 to 30 minutes, once)

Meta changes its screens and permission names often. Treat these steps as a map and check them against Meta's own Marketing API documentation (<https://developers.facebook.com/docs/marketing-api/get-started>).

1. **Create an app.** In <https://developers.facebook.com/apps> choose **Create app**, pick the use case about **advertising and promoting** (or the Business type), link it to your business portfolio, and add the **Marketing API** product.
2. **Create a System User.** In **Business Settings → Users → System users**, add one (give it the **Admin** role). A System User is a robot account: its token does not expire and does not depend on a person staying logged in.
3. **Give it your assets.** Select the System User, choose **Add assets**, and assign your **ad account** (full control) and your **Facebook Page**. Without the Page, creating ads fails.
4. **Generate the token.** On the System User choose **Generate new token**, pick your app, and tick **`ads_read`** and **`ads_management`**. Copy the token at once: Meta shows it only one time. For read only use, `ads_read` alone is enough.
5. **Find your ad account id.** In Ads Manager open **Settings**: the number under *Account overview* is it. Use only the digits (for example `1234567890`), not the `act_` prefix.
6. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **meta-ads** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Access token | The token, written as `${META_ADS_ACCESS_TOKEN}` with the real value in the Pepe server's environment, so it never sits in the settings file |
   | Ad account id | The number from step 5. Optional, but it saves repeating it |
   | Facebook Page id | Leave empty for now (see step 8) |
   | Instagram account id | Leave empty for now (see step 8) |
   | Allow creating | `no` (the default) is read only. `yes` lets the agent create and change things, always PAUSED |
   | Highest daily budget | The most a daily budget may be, in whole units like `50`. Required to write any budget. A lifetime budget may be at most this times its days |
   | Allow turning on | `no` (the default): the agent can never start spending. `yes` lets it turn on things whose budgets are within the limit |
   | Graph API version | Optional, like `v23.0` |

   The same settings can come from the environment: `META_ADS_ACCESS_TOKEN`, `META_ADS_ACCOUNT_ID`, `META_ADS_MAX_DAILY_BUDGET`, and the others in the same style.
7. **Give the tools to an agent, reading first:**

   ```bash
   pepe agent tools my-agent --add meta_ads_accounts,meta_ads_pages,meta_ads_campaigns,meta_ads_adsets,meta_ads_ads,meta_ads_insights
   ```

   Ask: *"list my ad accounts"* and *"how did my campaigns do in the last 7 days?"*
8. **Let the plugin find the Page and Instagram ids.** Ask the agent: *"show my Pages and Instagram accounts"* (`meta_ads_pages`). Copy the Page id, and the Instagram id of the profile you want, into the two empty fields of step 6.
9. **Only then turn writing on.** Set *Allow creating* to `yes`, set a small *Highest daily budget*, add the create tools to the agent, and ask for a draft. It is created PAUSED: open the link it gives you in Ads Manager and review it. Turn *Allow turning on* to `yes` only when you trust the flow; until then you switch drafts on yourself in Ads Manager.

If something is wrong the tool says what: the token expired or lacks a permission, the Page or ad account is not assigned to the System User, the account has no payment method, or Meta refused the ad (its own message is passed on).

## Keep it safe (this plugin can spend real money)

- **Writing is off** until you set *Allow creating* to `yes`.
- **Everything the agent creates is PAUSED.** Nothing spends until something turns it on.
- **Turning on is a separate switch** (*Allow turning on*), and before any turn-on the plugin checks every budget involved (the ad, its ad set and its campaign) against *Highest daily budget*. Budgets above it are refused.
- A budget cannot be written at all without the limit set, and one above it is refused before any request.
- Every write asks for approval unless you pre-approve it. Do not pre-approve `meta_ads_set_status`.
- What comes back from Meta (names, ad text, feedback) is written by other people, so it reaches the model framed as quoted material, never as instructions.
- Some audiences are restricted by Meta (housing, employment, credit, politics). The agent must name the special ad category; it never guesses.
