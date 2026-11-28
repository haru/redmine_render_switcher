---
title: Textile color span notation (%{color:red}text%) scoring
type: decision
sources: [S009, S010]
updated: 2026-11-27
---

# Textile color span notation (`%{color:red}text%`) scoring

Textile's color span notation scores 3 points for Textile, via the
`TEXTILE_COLOR_SPAN` constant added to the pattern table. Textile renders
`%{color:red}NG%` as `<span style="color:red;">NG</span>` while CommonMark
leaves the characters as plain text, which passes the "renders differently"
test of ADR-0005. The trigger was issue #16: over 256,957 production texts,
39,633 changed structurally after a Markdown switch, and 4,541 of them were
caused by color spans alone — the largest single named cause. Recorded in
ADR-0008; `Detector::VERSION` went 7 to 8, so the cache key now ends in
`-rs8t2` (see [cache key](./cache-key-detector-version.md)). (S009, S010)

## Only a `color` property counts

The style block counts only when it holds a `color` property: a name that is
exactly `color` (case-insensitive) followed immediately by `:`, placed right
after `{` or after a `;`-ended property, whitespace allowed in between. Mixed
blocks count (`%{font-weight:bold; color:red}x% y`). (S009)

- **Why `color` only:** issue #16 measured color spans alone; no occurrence
  data exists for `background`, `font-size` or any other property, and YAGNI
  forbids scoring shapes nobody measured. (S009)
- **Not counted although Textile renders a span:** `background`,
  `font-size`, `background-color`, `border-color` (the name is not `color`),
  `color :red` and `color : red` (Redmine throws the style away and renders a
  bare `<span>`), a block without any colon (`件数は %{count}件% です` — the
  shape of Ruby i18n format strings), a `{…}` spanning two lines, and an
  empty body `%{color:red}%`. Bodies decorated only with such spans stay
  undecided and keep rendering as Markdown, where the decoration is lost —
  accepted recall loss. (S009)

## Boundaries follow RedCloth's QTAGS :limit rules

The opener sits at the start of a line or after whitespace, `(`, `>` or `|`
(the `|` being the same table-cell approximation as the image pattern),
optionally preceded by up to two `*` (strong text around a span). The body is
non-empty, stays within its paragraph (no blank line, LF or CRLF) and does not end with
whitespace. The closer is followed by end of line, whitespace or punctuation,
written as `[[:punct:]]` because RedCloth itself tests punctuation that way —
full-width Japanese punctuation (`、` `。` `！` `）` `」`) matches too. The
body is matched lazily, repeating RedCloth's own `.*?` behaviour, so
`結果は %{color:red}NG%でした。次は 50% です` closes at the later valid `%`
exactly as RedCloth does. The expression is ASCII-only and fixes no encoding.
(S009, S010)

## Measured trade-offs, accepted

- **Missed:** a body ending at a newline (`%{color:red}a\n%`), a class
  attribute before the style block (`%(cls){color:red}x% y`), and emphasis
  other than `*`/`**` around the span (`_%{color:red}x%_`). Textile colors
  all of them; they score nothing. (S009)
- **Over-detected:** a `|` that is not a table cell (`a|%{color:red}x% y`),
  and values Redmine's `STYLES_RE` rejects (`%{color:rgb(1,2,3)}x% y`,
  `%{color:}x% y`) — the latter still leave a bare `<span>`, so the notation
  disappears from the page either way. Pinned by the residual fixtures. (S009)
- **Inline code with spaces** (`` `a %{color:red}NG% b` ``): a backtick is
  not code in Textile, so the span after the space renders; the shape is
  counted, but the Markdown backticks score 3 in return and the document
  ties 3:3, so the verdict does not move. Inline code without spaces
  (`` `%{color:red}NG%` ``) fails the opener boundary and counts nothing. (S009)
- **Performance:** the lazy body repeats RedCloth's own `.*?` behaviour, so
  pathological inputs degrade at the same rate as RedCloth's rendering
  (34 ms against 76 ms per 10,000 one-line occurrences); ordinary 20,000-line
  documents scan in 8 ms. (S009)

## Rejected alternatives

- Any `{…}` holding a colon (`%{count}` included): Ruby i18n format strings
  appear in ordinary Markdown prose, and Textile renders such a block as a
  bare `<span>` with no decoration. (S009)
- A loose `\bcolor\s*:`: matches `background-color` (a different property,
  kept by Redmine) and `color :red` (whose style Redmine discards). (S009)
- A negated lookbehind `(?<![^\s(>|*])` for the opener: admits
  `a*%{color:red}x%*`, which Textile does not render — hence the separate
  `\*{0,2}` after a valid position. (S009)
- Scoring other styled properties too: deferred, not rejected — revisit when
  occurrence data arrives. (S009)

## Verification

Fixtures are checked against RedCloth's real output through the shared
counted / not-notation / missed / residual helper plus a dedicated list for
the styled-without-color spans (the one deliberate disagreement with
Textile's rendering), and pin the 3:0 verdict for a lone span (LF and CRLF),
both site settings rendering `<span style="color:red;">NG</span>`, a
markdown directive beating the score, and a section-edit round trip. (S009, S010)

## See also

[Detector design](./detector-design.md) ·
[Image scoring](./detector-textile-image.md) ·
[Insertion scoring](./detector-textile-insertion.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Cache key](./cache-key-detector-version.md)
