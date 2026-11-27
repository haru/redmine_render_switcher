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

## Measured trade-offs, accepted

- **Over-detected:** repeating an attribute kind counts — `!(a)(b)c.png!`,
  `!{a: b}{c: d}e.png!` — although Textile renders no image. RedCloth reads the
  three attribute kinds in three fixed orders; listing them would triple the
  expression for a shape that rarely occurs in prose. Attributes in an order
  RedCloth rejects (`!(c)[ja]{w: 1px}a.png!`) count for the same reason. A `|`
  or `>` that is not a table cell (`a |!a.png! b`, `<p>!a.png!</p>`) also
  opens an image. Pinned by the `IMAGE_RESIDUAL` fixtures. (S007, S008)
- **Missed:** dotless names (`!wow!`, `!img_1!`), an image wrapped in other
  notation (`==!a.png!==`), and any attribute block or alternative text
  spanning two lines (`!a.png(alt\ntext)!`, `!(a\nb)c.png!`) render as images
  but score nothing — every bracketed part stops at the newline. (S007)
- **No longer counted (all unrendered by Textile anyway):** notation glued to a
  word (`x!a.png!`, `これは!a.png!`), bracket-adjacent prose (`(!a.png!)`,
  `「!a.png!」`, `すごい!(笑)次はa.png!`), file names holding `(` (RedCloth
  reads it as alternative text), and the "dot plus space" branch
  `!{width: 1px}. a.png!` — the only over-detection of the first candidate, so
  the RedCloth `IMAGE_RE` `(?:\. )?` branch was left out. (S007)
- **Inline code with the plain notation now leans Markdown** (0:3):
  `` `!a.png!` `` scored 3:3 under the old pattern; the backtick scores for
  CommonMark while the notation stops matching. The styled shape in inline
  code never matched the old pattern and is unchanged. (S007)
- **Performance:** `scan` over pathological 300,000-character single lines
  stayed within 15 ms — linear; brackets stop at the newline, so no
  cross-line backtracking. (S007)

## Rejected alternatives

- The issue #15 proposal `/!(?:\{[^}\n]*\})?\S*[.\/]\S*!/`: covers only the
  pasted shape, misses alignment/class/language/alt-text-with-spaces, and has
  no opener condition, so `x!a.png!` keeps counting. (S007, S008)
- Adding only a `{…}` branch to the old pattern: same gaps remain. (S007)
- Dropping the opener condition: every `!` next to `{` or `(` in prose
  (`Wow!{a b} c.d!`, `Error!(code) x.rb!`) would score and switch Markdown
  documents for nothing. (S007)

## Verification

New tests compare the pattern directly with RedCloth's rendering through one
shared helper (counted / not-notation / missed / residual input groups) and pin the 3:0 verdict for a
lone pasted image, the CRLF document shape, functional rendering under both
site settings, and a section-edit round trip. (S007, S008)

## See also

[Detector design](./detector-design.md) ·
[Insertion scoring](./detector-textile-insertion.md) ·
[Color span scoring](./detector-textile-color-span.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Cache key](./cache-key-detector-version.md)
