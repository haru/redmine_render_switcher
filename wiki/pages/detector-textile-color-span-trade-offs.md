---
title: Color span — trade-offs and rejected alternatives
type: decision
sources: [S009, S011]
updated: 2026-11-28
---

# Color span — trade-offs and rejected alternatives

Companion to [Textile color span scoring](./detector-textile-color-span.md)
(ADR-0008, `Detector::VERSION` 8). (S009)

## Measured trade-offs, accepted

- **Missed:** a body ending at a newline (`%{color:red}a\n%`), a class
  attribute before the style block (`%(cls){color:red}x% y`), and emphasis
  other than `*`/`**` around the span (`_%{color:red}x%_`), or three stars
  around it (`***%{color:red}x%*** y`). Textile colors all of them; they
  score nothing. (S009, S011)
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

## Pinned by fixtures

The gaps above cannot widen or close unnoticed: the detector test keeps them
in `COLOR_SPAN_MISSED` and `COLOR_SPAN_RESIDUAL`, notation Textile renders
as a bare undecorated `<span>` (`%{background:yellow}x% y`, a multi-line
`{…}`) in `COLOR_SPAN_NOT_COLORED`, and prose such as `50% と 80%` or
`結果は%{color:red}NG%でした` (no boundary on either `%`) in
`COLOR_SPAN_NOT_NOTATION`. Prose with `%` therefore stays Markdown. (S011)

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

## Re-verify when Redmine updates its formatters

Check that Textile still renders `%{…}…%` as a styled span at these
boundaries, that RedCloth's `QTAGS` `:limit` rules and `STYLES_RE` are
unchanged, and that CommonMark still leaves the notation as plain text.
The pattern is ASCII-only, but invalid byte sequences still raise, by
design. (S011)

## See also

[Color span scoring](./detector-textile-color-span.md) ·
[Detector design](./detector-design.md) ·
[Line patterns](./detector-line-patterns.md)
