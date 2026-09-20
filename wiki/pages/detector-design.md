---
title: Detector design
type: component
sources: [S001, S002, S003, S004]
updated: 2026-09-20
---

# Detector design

## Structure

A single class, `RedmineRenderSwitcher::Detector`, runs four steps: (1) strip
code blocks, (2) add points from a frozen pattern table, (3) apply line-context
rules, (4) compare against the threshold. It returns a `Detector::Result` with
the chosen format, both scores and a `reason` (four possible values), so every
decision is explainable. (S001, S002)

> ⚠ conflict: S001 and S002 describe step 3 as one context rule, for `#` lines,
> and step 1 as fences and `<pre>`. S003 and S004 make step 3 four rules (`#`
> lines, list blocks, table blocks, Setext headings) and extend step 1 to
> four-space and tab indented blocks. The later design applies; see
> [scan structure](./detector-scan-structure.md). (S001, S003)

It also owns `Detector::VERSION`, which feeds the
[cache key](./cache-key-detector-version.md); the rule revision bumped it from
3 to 4. (S002, S003)

## Ambiguity is solved by context, not patterns

Naive scoring reads Textile's numbered-list `# item` as a Markdown `h1`. The fix
is a line-context rule: two or more consecutive `#` lines mean a Textile numbered
list, a lone `#` line means a Markdown heading. (S001) The later rules follow the
same shape: lists, tables and Setext headings are all context rules, none is a
new bare pattern. (S004)

## Scoring policy

- Notation both formats render the same scores 0 or very low: `* list`,
  `> quote`. (S001)
- `**bold**` is no longer scored: both formats render it as bold, so it carries
  no information. (S003, S004)
- Decisive Textile: `h1.`–`h6.`, `"text":url`, `!image!`, `bq.`, `@code@`,
  `|_. header`. Decisive Markdown: fenced code, `[text](url)`, `![](url)`,
  `` `code` ``, `|---|`. (S001, S003)
- New structural evidence: dash and numbered lists, Setext headings, and tables
  with or without a separator row, counted once per block. Weights and rationale:
  [score once per block](./detector-score-once-per-block.md). (S003)

> ⚠ conflict: S001 lists `**bold**` among the decisive Markdown patterns and
> `|table|` among the unscored ones. S003 removes `**bold**` and scores tables
> by block: 4 for Textile without a separator row, 5 for Markdown with one. The
> later decision applies. (S001, S003)

- The winner must lead by at least the threshold (default 2, see
  [settings](./plugin-settings.md)); otherwise no switch happens. (S001, S002)
- Precision before recall: a rule that could cause a wrong switch is not adopted
  even if it misses documents (FR-020). (S003)

## Decisions

- **One class, no split.** The `.rubocop.yml` Metrics limits (ClassLength 650,
  MethodLength 70, CyclomaticComplexity 15) are loose enough, and KISS applies. (S001)
- **Rejected:** adding more patterns for the `#` case, and ML or an external
  library (extra dependency, loses explainability, violates Constitution IV). (S001)
- Detection costs well under 5% of a render, and runs once per instance. (S002, S003)
- Table-driven unit tests are the centre of TDD. (S002)
- `Detector.detect` and `Directive.parse` are non-destructive. (S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Accepted behaviour changes](./detector-revision-accepted-changes.md) ·
[Directive](./directive-html-comment-form.md) ·
[AutoSwitch](./auto-switch-module.md) ·
[Logger](./plugin-logger.md)
