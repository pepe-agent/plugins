---
name: meta-ads-campaign-builder
description: Turns a short brief into a paused, review-ready Meta Ads campaign (objective, audience, budget, creative) with the safe defaults. Use when the user asks to create, set up or launch a Facebook or Instagram ad campaign ("cria uma campanha", "quero anunciar isso", "monta um anúncio de conversão").
compatibility: Needs the meta-ads plugin (pepe plugin install @jhonathas/meta-ads) with its create tools given to the agent and "Allow creating" turned on.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Meta Ads campaign builder

Build a draft a person can review in Ads Manager. Everything is created **paused**; you never spend money by building.

## 1. Get the brief (ask only what is missing)

- **Goal** in the user's words, mapped to an objective: more visits (`traffic`), brand reach (`awareness`), messages or post interaction (`engagement`), leads (`leads`), purchases (`sales`), app installs (`app_promotion`).
- **Where people land**: the page address (https).
- **Who**: country or city, age range, and any interest the user names.
- **Money**: a daily budget and how long it runs. If they say "R$ 300 for the week", that is about R$ 43 a day.
- **The ad**: the picture or video address (public https), the main text, a short headline, the button.
- **Sensitive category?** If the ad is about housing, employment, credit, or social and political topics, Meta restricts targeting and requires declaring it. Ask. Never guess `special_ad_category`; use `none` only when the user confirms none applies.
- For `sales`, the **pixel** (`meta_ads_pixels` lists them). For `leads`, the Page must be configured.

## 2. Check before building

1. `meta_ads_accounts` to confirm the account, its currency and that it is active.
2. Search ids instead of guessing: `meta_ads_search_targeting` for interests and cities.
3. `meta_ads_estimate` with the planned audience. Too small (a few thousand) or huge (nearly everyone) is a reason to adjust before spending.
4. Pick a budget within what the operator allowed. If the user asks for more than the configured limit, say the limit and stop; do not look for a way around it.

## 3. Build

Prefer `meta_ads_create_draft`: campaign, ad set, creative and ad in one call, with rollback if a step fails. Use the separate create tools only when the brief needs something the draft does not cover (a carousel, an existing post, several ads).

Name things so a person can find them: "2026-10 Launch | Traffic | BR 25-45".

## 4. Hand over

Give the user the review link from the result and a short summary: objective, audience and its estimated size, budget and dates, what the ad says. State plainly that **everything is paused and nothing is spending**. Turning it on is theirs to do in Ads Manager, unless the operator enabled it and the user asks you in this turn.

## Rules

- One campaign per request unless asked otherwise. No "while I'm at it" extras.
- If a step is refused, pass on Meta's own message and what to fix; do not retry with invented values.
- Do not reuse the same name for different tests; see meta-ads-ab-test for comparisons.
