---
title: Textile insertion notation (+text+) scoring
type: decision
sources: [S005, S006]
updated: 2026-10-31
---

# Textile insertion notation (`+text+`) scoring

`+text+` scores 3 points for Textile per occurrence, via the `TEXTILE_INSERTION`
constant added to the pattern table next to `TEXTILE_INLINE_CODE`. No new context
rule or scan was needed: the ambiguity of `+` is decided by the characters around
one notation, never across lines. Recorded in ADR-0006; `Detector::VERSION` went
5 to 6. (S005, S006)

## Why it was added

Textile renders `+text+` as `<ins>`; CommonMark leaves the plus signs as text.
A filled-in template whose only Textile markup was `+*label:*+` scored 0:0 and fell
back to the site format, so on a Markdown site it showed stray plus signs. The
earlier "too rare" ruling (ADR-0005) was therefore dropped for this notation
only; `-del-`, `%span%`, `fn1.` and the `+ ` bullet stay unscored. (S005, S006)

## What counts

- The opening `+` follows a line start, whitespace or `(`; it may also follow a
  `*` that starts a line or follows whitespace, or a `|` that starts a line. (S006)
- The closing `+` precedes a line end, whitespace, or one of `. , ; : ! ? ) * |`
  and the full-width full stop, comma and parenthesis. (S006)
- The content is at least two characters, stays on one line, does not begin or end
  with whitespace and holds no `+`. So `+a+`, `++x++` and `C+++` score nothing. (S005)
- Code blocks stay masked like any other notation. (S006)

> ⚠ conflict: S005 gives the regex with the opening boundary `(?<![^\s(*|])`
> (a `*` or `|` anywhere before it is allowed). The shipped code and ADR-0006 are
> stricter (`x*+ab+*y` and `x |+ab+| y` do not count). Code wins; research.md
> predates the "refine pattern boundaries" fix. (S005)

## Measured trade-offs, accepted

- **Missed:** `+a b+c+`, `+ab+cd+`, `+a+b+ x`, `+ab + cd+` render `<ins>` in
  Textile but score nothing, because a `+` inside the content would let `++x++`
  match. Without other evidence the site setting decides. (S005)
- **Over-detected:** `+bc+` set apart by spaces inside inline code, a link label,
  `<code>` or `<notextile>` still scores. One occurrence ties 3:3 or 3:4 and does
  not switch; two or more in one code span, or any in `<code>`/`<notextile>`, do
  switch. Masking was rejected as YAGNI; the directive is the escape hatch. (S005)
- **Not whitespace:** U+3000 and U+00A0 are not boundaries; Textile does not
  render them as insertion either (Ruby's ASCII `\s` is used). (S005)
- **No encoding guard:** the full-width marks make the pattern UTF-8 only, so a
  non-ASCII non-UTF-8 string raises `Encoding::CompatibilityError`. The two
  formatters already raise on the same input and core callers normalise to UTF-8
  first, so no guard (Constitution III). (S005)

## Verification

A 58-example table was checked against Textile's real output with no mismatch, and
the `Detector::VERSION` floor test is the only existing test that pins the number.
New tests compare the pattern with RedCloth directly. (S005, S006)

## See also

[Detector design](./detector-design.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Score once per block](./detector-score-once-per-block.md) ·
[Cache key](./cache-key-detector-version.md)
