---
title: Detector line patterns and their traps
type: component
sources: [S003, S004]
updated: 2026-09-20
---

# Detector line patterns and their traps

The line-context rules in [detector design](./detector-design.md) rest on seven
constants in `detector.rb`, each measured against Redmine 7.0.1. (S003)

| Constant | Regex | Used for |
|---|---|---|
| `MARKDOWN_LIST_LINE` | `/\A(?:-\|\d+\.)[ \t]/` | scored list lines |
| `SETEXT_UNDERLINE` | `/\A=+\s*\z/` | Setext underline |
| `TABLE_LINE` | `/\A\|.*\|\s*\z/` | table rows |
| `MARKDOWN_TABLE_SEPARATOR` | `/\A\|[\s:\|-]*-[\s:\|-]*\|/` | separator row (moved from the old whole-text pattern to a per-line test) |
| `INDENTED_LINE` | `/\A(?: {4}\|\t)/` | indented-code masking |
| `BLANK_LINE` | `/\A\s*\z/` | blank-line test |
| `LIST_ITEM_LINE` | see conflict below | masking start and Setext context |

(S003)

## Why they look like this

- **`TABLE_LINE` needs a closing pipe.** `| pipe one | pipe two` is not a Textile
  table (measured `<p>…</p>`); requiring it makes the FR-023 false-positive
  check (Markdown text with leading pipes) pass. (S003)
- **Scored patterns are anchored to column 0.** This is the FR-022 invariant.
  Textile does tabulate an indented `  | a | b |`, but the plugin picks the
  *miss* side (FR-020), and allowing indent would count rows inside indented code. (S003)
- **`\d+\.`, not `1\.`**: `7. seventh` renders as `<ol start="7">`. (S003)
- **One `=` is enough for a Setext underline** (`Title` / `=` renders `<h1>`), but
  not under a blank line or a list item, where Markdown also declines. Hence the
  context condition. (S003)
- **End line patterns with `\s*\z`, never `[ \t]*\z`.** Line strings keep their
  trailing newline; the prototype's first version broke all masking this way.
  Test rows C-4-1 and C-2-5 catch the mistake. (S003, S004)
- **`LIST_ITEM_LINE` is not anchored.** It is a context predicate ("may this
  line own a following indented line?"), not a scoring pattern, so nested items
  like `    - inner` must match. FR-022 governs scored patterns only. (S003)

> ⚠ conflict: S003 gives `LIST_ITEM_LINE` as `/\A[ \t]*(?:[-*]|\d+\.|#+)[ \t]/`,
> including `#+`. The current code (`detector.rb`) and CLAUDE.md omit `#+`: a `#`
> line may be a Markdown heading, which takes no continuation, so an indented
> block under it is code and must stay masked. Code wins. (S003)

## Deliberately not scored

`+ ` bullets and `N) ` numbered lists are read as lists only by Markdown
(`1) stop` renders `<ol>`), but FR-012 declines low-frequency notation for both
formats and this feature applies the same test. Adding them needs a spec
revision. (S003, S004)

## See also

[Score once per block](./detector-score-once-per-block.md) ·
[Scan structure](./detector-scan-structure.md)
