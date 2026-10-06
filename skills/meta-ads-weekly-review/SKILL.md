---
name: meta-ads-weekly-review
description: Produces a short, fixed-format weekly report of Meta Ads performance with what changed and what to do next. Use for a recurring review or a scheduled task, or when the user asks for a weekly summary of ads ("resumo semanal dos anúncios", "como foi a semana nos ads").
compatibility: Needs the meta-ads plugin (pepe plugin install @jhonathas/meta-ads) with its read tools. Pairs well with a Pepe scheduled task.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Meta Ads weekly review

A report someone reads in two minutes, the same shape every week so changes are easy to see.

## Collect

1. The last full 7 days and the 7 before, with `meta_ads_insights` at account level, then at campaign level.
2. `meta_ads_ads` for rejected or limited ads, and `meta_ads_campaigns` for anything paused or ended by mistake.
3. Only if something stands out, go deeper with the meta-ads-campaign-analysis skill. Do not dig into everything.

## Format

Use exactly these blocks, in this order, in plain language:

**Week** in one line: dates, total spend, total results, cost per result, each with the change against the week before.

**Best and worst**: the campaign with the best cost per result and the worst, with their numbers. Skip campaigns with trivial spend.

**What changed**: up to 3 bullets on the biggest movements and the most likely reason, each tagged data or hypothesis.

**Needs attention**: rejected ads, ads or ad sets that stopped delivering, budgets spent too fast or barely used, creatives with high frequency.

**Next**: up to 3 actions, most impact first. One of them may be a test (see meta-ads-ab-test).

## Rules

- Same currency, same definition of "result" every week. Say which one at the top.
- Quote the numbers you used; round for reading, never for deciding.
- A quiet week is a valid report: say "no relevant change" and stop.
- This skill only reads. It never edits or turns anything on.
