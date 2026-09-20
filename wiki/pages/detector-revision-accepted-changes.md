---
title: Detector revision — accepted behaviour changes and test rebuilds
type: reference
sources: [S003, S004]
updated: 2026-09-20
---

# Detector revision — accepted behaviour changes and test rebuilds

Measured on Redmine 7.0.1 with a prototype over the 22 existing test rows plus 30
new samples. Every verdict change below moves toward *not switching*, which is
within FR-020's tolerance for missing. (S003)

## Behaviour changes outside the existing table

| Sample | Before | After | Verdict |
|---|---|---|---|
| `h1. Title` plus `Release notes` over `=====` | textile 5:0 | below_threshold 5:4 | A Textile document with a `=` rule loses its verdict; no switch happens. |
| `[guide](url)` plus a 2-row table without separator | common_mark 0:4 | below_threshold 4:4 | Link and bare table tie; no switch. |
| Indent at the start of a text | textile 4:0 | textile 4:0 | Unchanged: the FR-014 limit. |

(S003)

## Existing test rows that had to be rebuilt

Removing `**bold**` changes only three rows, all built with `**` as a score source;
the other 20 keep their verdict and reason (D-01 rises 24 to 28, D-02 stays 30). (S003)

| Row | Purpose | Now |
|---|---|---|
| D-15 `NARROW_MARGIN` | margin of 1 | `bq.` (4) vs `` `code` `` (3), so 4:3 |
| D-17 `MARKDOWN_WITH_MENTIONS` | mentions do not tilt to Textile | a two-line `- ` list (3), so 0:3 |
| `EXACT_TIE` | equal scores | `@code@` (3) vs `` `code` `` (3), so 3:3 |

After the rebuild D-15 is still `below_threshold`, Textile still wins by 1 at
threshold 0, and the tie stays 3:3, so the FR-018 boundary cases stay pinned
(SC-009). (S003)

**Order matters:** rebuild these rows before deleting `**`, so the suite stays
green throughout. Also pin the `h1.` plus dash-list document at 5:3 for both a
2-line and a 5-line list (C-5-8): it guards the Textile-flip risk. (S004)

## See also

[Score once per block](./detector-score-once-per-block.md) ·
[Detector design](./detector-design.md)
