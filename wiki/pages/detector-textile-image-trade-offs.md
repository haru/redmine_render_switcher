---
title: Image scoring — trade-offs and verification
type: decision
sources: [S007, S008]
updated: 2026-11-28
---

# Image scoring — trade-offs and verification

Companion to [Textile image notation scoring](./detector-textile-image.md)
(ADR-0007, `Detector::VERSION` 7). (S007, S008)

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

[Image scoring](./detector-textile-image.md) ·
[Detector design](./detector-design.md) ·
[Line patterns](./detector-line-patterns.md)
