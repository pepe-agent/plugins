---
name: meta-ads-ab-test
description: Designs and reads a clean Meta Ads test (one change, same audience, enough data) and builds the variant paused for review. Use when the user wants to test a creative, copy, audience or budget, or wonders which of two ads is better ("quero testar dois criativos", "qual anúncio é melhor", "faz um teste A/B").
compatibility: Needs the meta-ads plugin (pepe plugin install @jhonathas/meta-ads). Building a variant needs its create tools and "Allow creating" turned on; reading results needs only the read tools.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Meta Ads A/B test

A test answers one question. If two things change at once you learn nothing.

## 1. Write the test down first

Before touching anything, state to the user in 4 lines:
- **Question**: for example "does the video beat the image?".
- **The one thing that differs**: creative, headline, audience, or placement. Everything else stays identical.
- **The measure**: one result (cost per lead, cost per purchase, CTR). Choose it now, not after seeing the data.
- **When to stop**: a budget and a number of days, for example 7 days and enough budget for at least 50 results per variant. State it so nobody ends the test early because one side looks ahead.

## 2. Build the variant

- Same audience and budget in both arms. The cleanest way is two **ads inside the same ad set**; to test audiences, two **ad sets** with equal budgets and the same ad.
- To copy what exists, `meta_ads_duplicate` (the copy is paused), then change only the one thing with `meta_ads_update`, or add the new ad with `meta_ads_create_creative` and `meta_ads_create_ad`.
- Everything is created **paused**. Give the user the review link and let a person check the ad and turn it on. Only turn it on yourself if the operator allowed turning on and the user asks.
- Name the arms so the result reads itself, for example "Test video vs image, A: video".

## 3. Read it

After the planned days, `meta_ads_insights` for each arm at the same level and period.

1. Check **both arms delivered** (similar spend and impressions). If one barely ran, the test is void, not won.
2. Compare the chosen measure. Report the difference as a percentage.
3. Check the sample: under roughly 50 results per arm, or a gap of a few percent, call it **inconclusive** and say what it would take to know (more days or budget). A small win on small numbers is noise.
4. Only then recommend: keep the winner, pause the loser (ask first), and propose the next single test.

## Rules

- Never change an arm in the middle of the test; editing an ad set also restarts its learning.
- Do not declare a winner on a metric chosen afterwards.
- Say plainly when the answer is "no clear difference": that is a result too.
