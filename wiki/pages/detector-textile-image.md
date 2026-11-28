---
title: Textile image notation (!…!) scoring with styled attribute blocks
type: decision
sources: [S007, S008, S009]
updated: 2026-11-27
---

# Textile image notation (`!…!`) scoring with styled attribute blocks

Textile's image notation scores 3 points for Textile, via the `TEXTILE_IMAGE`
constant that replaced the old `%r{!\S*[./]\S*!}` row in the pattern table. The
old pattern missed the shape Redmine's clipboard paste writes,
`!{width: 794px}.clipboard-….png!`, because the style block holds spaces — on a
Markdown site the pasted body kept rendering as raw text (issue #15). Recorded
in ADR-0007; `Detector::VERSION` went 6 to 7, so the cache key ended in
`-rs7t2` at the time (it has since moved to `-rs8t2` with the color span
pattern; see [cache key](./cache-key-detector-version.md)). (S007, S008, S009)

## The pattern follows RedCloth's grammar

The rule was derived from RedCloth itself (`IMAGE_RE` and the `C_CLAS` /
`C_STYL` / `C_LNGE` attribute rules of `redcloth3.rb`), not written from
intuition, and checked against Textile's real output: all 45 inputs of the spec
background table agreed with what Textile renders. (S007)

- The opening `!` counts at the start of the text and after whitespace, `>` or
  `|`. Written as the negative lookbehind `(?<![^\s>|])`, unlike
  `TEXTILE_INSERTION`, which needs an explicit `^` branch: `\s` covers the
  newline, so CRLF and line starts share one expression. Textile reaches a
  table cell through the `>` of its generated `<td>`; the `|` is the plugin's
  own approximation, so a `|` outside a table also counts. (S007, S008)
- The attribute block accepts alignment (`<`, `=`, `>`), class/id parentheses,
  style braces and language brackets in any order and any number, with spaces
  inside (`!(my cls){width: 1px}[ja]a.png(alt t)!`). (S007)
- The file name or URL must contain `.` or `/` and no whitespace, `(` or `!`.
  A dotless name such as `!wow!` is a deliberate miss: Textile renders it as an
  image, but it is the shape most likely to appear in prose. (S007)
- The alternative text allows spaces and one level of nested parentheses after
  at most one space (not a tab, not two spaces), on one line
  (`!a.png(alt text)!`). (S007)

## Trade-offs, rejected alternatives and verification

The accepted over-detections and misses, the performance measurement, the
rejected pattern shapes and the RedCloth cross-check live on
[Image scoring — trade-offs and verification](./detector-textile-image-trade-offs.md).
(S007, S008)

## See also

[Detector design](./detector-design.md) ·
[Insertion scoring](./detector-textile-insertion.md) ·
[Color span scoring](./detector-textile-color-span.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Cache key](./cache-key-detector-version.md)
