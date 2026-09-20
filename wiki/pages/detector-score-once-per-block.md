---
title: Score new detector evidence once per block
type: decision
sources: [S003, S004]
updated: 2026-09-20
---

# Score new detector evidence once per block

Feature 002 adds four structural rules to the [detector](./detector-design.md).
Two choices shape all of them: evidence is counted per *block*, and a list needs
at least two lines. (S003, S004)

## Weights

| Rule | Evidence for | Weight | Counted |
|---|---|---|---|
| Markdown list block (`- ` or `N. `, 2+ lines in a row) | Markdown | 3 | once per block |
| Setext underline (a line of `=`) | Markdown | 4 | per occurrence |
| Table block without a separator row (2+ lines) | Textile | 4 | once per block |
| Table block with a separator row | Markdown | 5 | once per block |

(S003)

## Why per block

Counting per line makes evidence grow with length. Worst case, a Textile document:

```
h1. Notes

- one
- two
...five dash lines
```

At 2 points per dash line it scores Markdown 10 against Textile 5 and flips to
Markdown. At 3 points per block it scores 5:3 and stays Textile, whatever the
list length. The cap is the point: precision comes before recall (FR-020, "miss
rather than break"). (S003)

Weights are ordered against the existing table: one structural rule (3 or 4)
cannot overturn a link (4) or a heading (5) alone; a separator-less table sits
below `|_.` (5) and level with links; the Markdown table keeps its old weight 5,
so the D-02 sample stays at 30 points. (S003)

> ⚠ conflict: S003 defines a list block as lines that are "consecutive"; the
> current code and ADR-0005 let blank lines between items stay in the same block.
> The ADR and code win. (S003)

## Why two lines minimum

FR-005 ("score a `- ` bullet as Markdown") and SC-008 ("prose containing a `- `
line stays neutral") cannot both hold literally. Measured: `Costs are stable.` /
`- see the note below` is a list in Markdown and plain text in Textile. The one
line that satisfies both is "two or more consecutive lines", the same rule FR-009
applies to tables (a lone leading-pipe line occurs in Markdown too). It narrows
FR-005 slightly: a document with a single `- ` line is missed, but no extra wrong
switch appears. (S003, S004)

## Rejected

- Per line at 2 points: flips the Textile document above.
- Per line at 1 point: no flip, but a margin of 1 erases the verdict and length
  dependence remains.
- Once per document: safest cap, but cannot tell one list from many and does not
  match the run-based `#` rule.
- Scoring a single dash line, or dropping the dash line from SC-008's sample:
  the first breaks Textile-site prose; the second loosens an acceptance criterion
  to suit the implementation. (S003)

## Record

FR-002 requires the scoring policy in **ADR-0005**; these two choices go in its
Consequences section. (S004)

## See also

[Line patterns](./detector-line-patterns.md) ·
[Scan structure](./detector-scan-structure.md) ·
[Accepted behaviour changes](./detector-revision-accepted-changes.md)
