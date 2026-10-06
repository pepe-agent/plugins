---
name: meta-ads-creative-fatigue
description: Detects creative fatigue and audience saturation in Meta Ads from frequency, CTR and CPM trends, and says which ads to rotate out. Use when results decay over time, the user asks if a creative is worn out, or when to renew ads ("o criativo cansou", "quando trocar o anúncio", "a frequência está alta").
compatibility: Needs the meta-ads plugin (pepe plugin install @jhonathas/meta-ads) with its read tools given to the agent.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Meta Ads creative fatigue

Fatigue means the same people saw the same ad too often, so it stops working. It shows up as a **trend**, not a single bad day.

## Get the trend

1. `meta_ads_ads` to list the active ads with their ad set.
2. For each meaningful ad (real spend, not a few cents), `meta_ads_insights` with `level` ad and `by_time` day over the last 14 to 30 days, or since the ad started if newer.
3. For the audience side, `meta_ads_insights` at ad set level with `reach` and `frequency` for the same window.

## The signs

Look for several of these moving together, over a week or more:

- **Frequency rising** while reach flattens: the same people again and again. As a rule of thumb, frequency above 3 to 4 in a week for a cold audience is a warning; retargeting tolerates more. Compare with the account's own history before calling it high.
- **CTR falling** for the same ad and audience.
- **CPM and cost per result rising** with no change in targeting or budget.
- **Negative signals**, when the data has them: falling relevance or rising hides and complaints.

One sign alone is weak. A new ad that still has a short history is not fatigued, it is just early.

## Fatigue or saturation?

- Ad CTR falls but a **new ad in the same ad set** performs well: the creative is worn out.
- Every ad in the ad set falls together and frequency is high: the **audience** is exhausted. Fixing the creative will not help much; widen the audience or add a new one (`meta_ads_estimate` shows the size).

## Report

For each ad: **healthy**, **watch** or **rotate**, with the 2 or 3 numbers behind it (frequency, CTR then and now, cost per result then and now). Then propose, in order: renew the creative (same offer, new angle or format), widen or refresh the audience, cap spend on the tired ad. Mark every cause as data or hypothesis.

If the user wants replacements built, follow meta-ads-ab-test so the new ad is compared properly, created paused, and reviewed by a person before anything runs.

## Rules

- Never call fatigue from fewer than about 7 days of data or very low delivery.
- Read only. Pausing or editing happens only when the user asks, one confirmed change at a time.
