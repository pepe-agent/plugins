---
name: meta-ads-campaign-analysis
description: Diagnoses why Meta Ads (Facebook and Instagram) campaigns got better or worse and what to change, from real numbers. Use when the user asks how campaigns are doing, why the cost per result went up, where the budget is wasted, or what to improve ("como estão as campanhas", "por que o CPA subiu", "onde estou jogando dinheiro fora").
compatibility: Needs the meta-ads plugin (pepe plugin install @jhonathas/meta-ads) with its read tools given to the agent.
metadata:
  author: jhonathas
  version: "0.1.0"
---

# Meta Ads campaign analysis

Work like a traffic manager: find where the result changed, form a cause from the numbers, say how sure you are, and end with actions ordered by impact. Everything comes from `meta_ads_*` read tools. Never invent a number.

## 1. Fix the question and the period

Ask only if missing: which account and which result matters (leads, purchases, clicks). Default to the last 7 days against the 7 days before. Compare equal lengths, and avoid periods with a holiday or a sale on one side only (say so if unavoidable).

## 2. Get the numbers, widest first

1. `meta_ads_insights` for the account, both periods, `level` campaign. Note spend, results, cost per result, CTR, CPM, frequency.
2. Find the campaigns that moved most in cost per result **and** carry meaningful spend. Ignore tiny spenders: their numbers are noise.
3. Go one level down only for those: `level` adset, then ad.
4. Then slice the worst ones with `breakdown` (age, gender, placement, country) and `by_time` (day) to see whether the problem is everywhere or one slice.
5. `meta_ads_ads` with status problems to catch rejected ads, and `meta_ads_adsets` to read budget, bid and audience.

Do not pull everything at once. Each step decides the next.

## 3. Read the pattern, then name the likely cause

| What moved | Likely cause | Check |
|---|---|---|
| CPM up for everyone | Competition or season, not your ads | Compare other campaigns, same dates |
| CTR down, frequency up | Creative fatigue or saturated audience | Use the meta-ads-creative-fatigue skill |
| CTR fine, conversions down | Problem after the click: page, price, tracking | Ask about site changes; check the pixel with `meta_ads_pixels` |
| One placement or age band far worse | Wasted spend in a slice | Breakdown; suggest excluding it |
| Spend flat, results fell, one ad set | Audience too small or overlap with another ad set | `meta_ads_estimate`, compare targeting |
| Delivery dropped suddenly | Rejected ad, limited budget, ended schedule | `meta_ads_ads`, `meta_ads_adsets` |
| Cost swings in the first days of a new or edited ad set | Learning phase | Do not judge yet; leave it alone |

Many causes sit outside the account (site, price, stock, season). You only see the account: when the data points past it, say "this looks like X outside the ads; confirm with whoever owns it".

## 4. Report

Short, in this order:
1. **Verdict** in one line (better, worse, flat, and by how much).
2. **Where**: the 2 or 3 campaigns, ad sets or slices that explain it, with their numbers.
3. **Why**, each cause marked **data** (shown by numbers) or **hypothesis** (inferred), with a confidence of high, medium or low.
4. **Actions**, most impact first: what to change, on which object, expected effect. Mark which are safe (pause, shift budget) and which need a test.

## Rules

- Say which period and currency every number refers to. Quote the exact figures you used.
- A small sample proves nothing: with fewer than about 100 clicks or 20 results on an object, say the data is too thin instead of concluding.
- Correlation is not a cause: offer a test (see meta-ads-ab-test) when the cause is a hypothesis.
- Analysis only changes nothing. Do not pause, edit or create anything unless the user asks for it in this turn, and then confirm each change.
