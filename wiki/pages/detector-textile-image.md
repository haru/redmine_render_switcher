---
title: Textile image notation (!…!) scoring with styled attribute blocks
type: decision
sources: [S007, S008]
updated: 2026-11-25
---

# Textile image notation (`!…!`) scoring with styled attribute blocks

Textile's image notation scores 3 points for Textile, via the `TEXTILE_IMAGE`
constant that replaced the old `%r{!\S*[./]\S*!}` row in the pattern table. The
old pattern missed the shape Redmine's clipboard paste writes,
`!{width: 794px}.clipboard-….png!`, because the style block holds spaces — on a
Markdown site the pasted body kept rendering as raw text (issue #15). Recorded
in ADR-0007; `Detector::VERSION` went 6 to 7, so the cache key now ends in
`-rs7t2` (see [cache key](./cache-key-detector-version.md)). (S007, S008)

## The pattern follows RedCloth's grammar

The rule was derived from RedCloth itself (`IMAGE_RE` and the `C_CLAS` /
`C_STYL` / `C_LNGE` attribute rules of `redcloth3.rb`), not written from
intuition, and checked against Textile's real output: all 45 inputs of the spec
background table agreed with what Textile renders. (S007)

- The opening `!` counts only at the start of the text, after whitespace, `>`
  or `|` — a table cell. Written as the negative lookbehind `(?<![^\s>|])`, the
  same trick `TEXTILE_INSERTION` uses: no separate branch for the start of the
  text, and `\s` covers the newline, so CRLF and line starts share one
  expression. (S007, S008)
- The attribute block accepts alignment (`<`, `=`, `>`), class/id parentheses,
  style braces and language brackets in any order and any number, with spaces
  inside (`!(my cls){width: 1px}[ja]a.png(alt t)!`). (S007)
- The file name or URL must contain `.` or `/` and no whitespace, `(` or `!`,
  which keeps `!wow!`-style emphasis from matching. (S007)
- The alternative text allows spaces and one level of nested parentheses after
  at most one space, on one line (`!a.png(alt text)!`). (S007)

## Measured trade-offs, accepted

- **Over-detected:** repeating an attribute kind counts — `!(a)(b)c.png!`,
  `!{a: b}{c: d}e.png!` — although Textile renders no image. RedCloth reads the
  three attribute kinds in three fixed orders; listing them would triple the
  expression for a shape that rarely occurs in prose. Pinned in contract C-4.
  (S007, S008)
- **Missed:** an alternative text spanning two lines (`!a.png(alt\ntext)!`)
  renders as an image but scores nothing — every bracketed part stops at the
  newline. (S007)
- **No longer counted (all unrendered by Textile anyway):** notation glued to a
  word (`x!a.png!`, `これは!a.png!`), bracket-adjacent prose (`(!a.png!)`,
  `「!a.png!」`, `すごい!(笑)次はa.png!`), file names holding `(` (RedCloth
  reads it as alternative text), and the "dot plus space" branch
  `!{width: 1px}. a.png!` — the only over-detection of the first candidate, so
  the RedCloth `IMAGE_RE` `(?:\. )?` branch was left out. (S007)
- **Inline code with the notation now leans Markdown** (0:3): the backtick
  scores for CommonMark while the notation stops matching. (S007)
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

New tests compare the pattern directly with RedCloth's rendering (counted /
not-notation / missed / residual input groups) and pin the 3:0 verdict for a
lone pasted image, the CRLF document shape, functional rendering under both
site settings, and a section-edit round trip. (S007, S008)

## See also

[Detector design](./detector-design.md) ·
[Insertion scoring](./detector-textile-insertion.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Cache key](./cache-key-detector-version.md)
