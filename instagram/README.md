# Instagram

See an Instagram account and its recent posts, and publish a photo, a carousel or a reel, from a Pepe agent. It uses Meta's official Instagram Graph API.

```bash
pepe plugin install @jhonathas/instagram
```

For a **Business or Creator** account (a personal one cannot be published to through the API).

## Tools

| Tool | Does | Changes Instagram? |
|---|---|---|
| `instagram_account` | Shows the account (name, followers, posts) and how many posts it may still publish through the API in the last 24 hours | no |
| `instagram_recent_posts` | Lists the latest posts with type, date, likes, comments and link | no |
| `instagram_publish_photo` | Publishes a photo with a caption | **yes, public at once** |
| `instagram_publish_carousel` | Publishes a carousel of 2 to 10 photos with a caption | **yes, public at once** |
| `instagram_publish_reel` | Publishes a reel (waits for Instagram to process the video first) | **yes, public at once** |

Instagram has no drafts in its API: a publish goes live immediately, and this plugin cannot take a post back. That is why publishing is off by default and every publish asks first.

## What you need before starting

- An Instagram **Business or Creator** account, **connected to a Facebook Page**. (In the Instagram app: Settings → Account type and tools → switch to a professional account. Then link a Page in the Page's settings under linked accounts.)
- A **Meta developer** account (<https://developers.facebook.com>), and an **app** there.
- **A public address for every picture and video.** Instagram downloads the media itself, so the file has to be reachable on the internet at an `https://` address (a bucket, Cloudflare R2, any host). The plugin takes those addresses; it does not upload files.

## Set it up (about 20 to 30 minutes, once)

Meta changes its screens and permission names often. Treat these steps as a map and check them against Meta's own documentation for the Instagram Graph API.

1. **Create an app.** In <https://developers.facebook.com/apps> choose **Create app**, pick a use case that lets you add the Instagram API (the **Business** type is the usual one), and add the **Instagram** product (Instagram API with Facebook login).
2. **Get a token with the right permissions.** Open the Graph API Explorer (<https://developers.facebook.com/tools/explorer>), choose your app, and generate a **User access token** with `instagram_basic`, `instagram_content_publish`, `pages_show_list` and `pages_read_engagement`. While the app is in **Development** mode, people who have a role in the app (you, as admin) can use these permissions on their own accounts without Meta's app review.
3. **Make the token last.** The Explorer's token lasts about an hour. Exchange it for a long-lived one (60 days) with the app id and secret, then ask `me/accounts` for your Page: the **Page access token** it returns, taken from a long-lived user token, does not expire. (Or create a **System User** in Meta Business Suite, give it your Page and Instagram account, and generate its token, which does not expire either.) Meta's documentation describes both.
4. **Find the Instagram account id.** With that token, ask the Page for its Instagram account: `GET /{page-id}?fields=instagram_business_account`. The number in `instagram_business_account.id` (like `17841400000000000`) is the id. It is **not** the @name.
5. **Fill in the plugin.** In the Pepe dashboard open **Plugins**, find **instagram** and choose **Configure**:

   | Field | What to put |
   |---|---|
   | Access token | The token, written as `${INSTAGRAM_ACCESS_TOKEN}` with the real value in the Pepe server's environment, so it never sits in the settings file |
   | Instagram account id | The number from step 4 |
   | Allow publishing | `no` (the default) means read only. Set `yes` to let the agent publish |
   | Graph API version | Optional. Like `v23.0`. Empty uses the plugin's default |

   The same settings can come from the environment: `INSTAGRAM_ACCESS_TOKEN`, `INSTAGRAM_USER_ID`, `INSTAGRAM_WRITES` (`yes`), `INSTAGRAM_API_VERSION`.
6. **Give the tools to an agent.** Only the ones you list are available to it:

   ```bash
   pepe agent tools my-agent --add instagram_account,instagram_recent_posts,instagram_publish_photo,instagram_publish_carousel,instagram_publish_reel
   ```
7. **Try it, reading first.** Ask the agent: *"show the Instagram account"*, then *"list the last 5 posts"*. Only then set *Allow publishing* to `yes` and try a post, with a picture from a public address you control.

If something is wrong the tool says what: the token expired or was revoked (create a new one), a permission is missing, Instagram could not download the picture (its own message says why), the video could not be processed, or Instagram is rate limiting.

## Keep it safe

- **Publishing is off until you turn it on** (*Allow publishing*), and **every publish asks first**, unless you pre-approve it. Do not pre-approve the three publish tools: a post is public the moment it goes out and the API cannot take it back. The approval prompt shows the caption and the address of the media.
- Reading (`instagram_account`, `instagram_recent_posts`) is low risk, so pre-approving those is reasonable.
- **What comes back from Instagram is written by whoever can post to the account**, so it reaches the model framed as quoted material, never as instructions.
- Instagram allows about 100 API-published posts per account in 24 hours, and a carousel counts as one. `instagram_account` shows what is left.
- Use a **dedicated token** for Pepe and keep it out of repositories. A leaked token can publish on your account.

## Notes

- Photos must be JPEG. Instagram has rules for sizes and shapes (a carousel's pictures should share a shape) and for video format; they are in Meta's documentation, and a refused file comes back with Instagram's own message.
- A reel can take a minute to process. The plugin waits up to about a minute, and if Instagram is not done it says so and **does not publish**; try again later.
- A caption can have up to 2,200 characters (hashtags included); longer is refused before anything is sent.
- The extra protection for text that comes from Instagram (the run stops honoring `auto_approve` once it has read the account or its posts) needs a Pepe that knows `outside_content?/0`, from the release after 0.20. On an older Pepe the plugin works and still frames the text as quoted material.
- Installing shows a `caution` from Pepe's scan: the plugin reads environment variables (for the token) and uses the network. That is what it is for.

---

**Em português:** [README.pt-BR.md](https://github.com/pepe-agent/plugins/blob/main/instagram/README.pt-BR.md) (também na aba **Files** desta página).
