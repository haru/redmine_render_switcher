---
title: Detector design
type: component
sources: [S001, S002]
updated: 2026-09-19
---

# Detector design

## Structure

A single class, `RedmineRenderSwitcher::Detector`, runs four steps: (1) strip
code blocks, (2) add points from a frozen pattern table, (3) apply a context rule
for `#` lines, (4) compare against the threshold. It returns a
`Detector::Result` with the chosen format, both scores and a `reason` (four
possible values), so every decision is explainable. (S001, S002)

It also owns the `Detector::VERSION` constant, which feeds the
[cache key](./cache-key-detector-version.md). (S002)

## The `#` line problem

Naive scoring reads Textile's numbered-list `# item` as a Markdown `h1`. The fix
is a line-context rule rather than more patterns: two or more consecutive `#`
lines mean a Textile numbered list, a lone `#` line means a Markdown heading. (S001)

## Scoring policy

- Syntax that renders the same in both formats (`* list`, `> quote`, `|table|`)
  scores 0 or very low. (S001)
- Decisive patterns score high. Textile: `h1.`–`h6.`, `"text":url`, `!image!`,
  `bq.`, `@code@`, `|_. header`. Markdown: fenced code, `[text](url)`,
  `![](url)`, `**bold**`, `` `code` ``, `|---|`. (S001)
- Roughly 20 rules to start. (S002)
- The winner must lead by at least the threshold (default 2, see
  [settings](./plugin-settings.md)); otherwise no switch happens. (S001, S002)

## Decisions

- **One class, no split.** The `.rubocop.yml` Metrics limits (ClassLength 650,
  MethodLength 70, CyclomaticComplexity 15) are loose enough, and KISS applies. (S001)
- **Rejected:** adding more patterns (does not fix the `#` case), and ML or an
  external library (extra dependency, loses explainability, violates
  Constitution IV). (S001)
- Accuracy matters more than speed: detection costs about 0.29 ms against 14–48
  ms of rendering, and runs once per instance. (S002)
- Table-driven unit tests are the centre of TDD; the initial cases are the
  feasibility report's Textile and Markdown samples, and SC-002 requires all of
  them to match. (S002)
- `Detector.detect` and `Directive.parse` are non-destructive. (S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Directive](./directive-html-comment-form.md) ·
[AutoSwitch](./auto-switch-module.md) ·
[Logger](./plugin-logger.md)
