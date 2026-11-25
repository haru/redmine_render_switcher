# ADR-0007: Score Textile image notation with RedCloth's grammar, including styled attribute blocks

- **Status**: Accepted
- **Date**: 2026-11-25

## Context

Redmine's clipboard paste inserts images into a Textile body as
`!{width: 794px}.clipboard-….png!`. The detector's image pattern,
`%r{!\S*[./]\S*!}`, does not match that shape: the style block contains
whitespace (`width: 794px`), so on a Markdown site the pasted body keeps
rendering as raw text instead of an image (issue #15).

The rule for where an image notation counts was measured the same way as in
[ADR-0005](./0005-score-only-notation-that-renders-differently.md) and
[ADR-0006](./0006-score-textile-insertion-notation.md), which this ADR
complements (neither is superseded): a candidate rule was compared against
Textile's actual output, produced by Redmine 7.0.1-stable with RedCloth. All
45 inputs of the spec's background table agreed with Textile's own treatment,
and `scan` over pathological inputs (a single 300,000-character line) stayed
within 15 ms, in line with the ~10 ms measured for ADR-0006. The evidence
lives in `specs/004-detect-styled-textile-image/research.md`.

## Decision

1. **The image pattern follows RedCloth's grammar** (`IMAGE_RE` and the
   `C_CLAS` / `C_STYL` / `C_LNGE` attribute rules of `redcloth3.rb`), encoded
   as the `TEXTILE_IMAGE` constant:

   ```ruby
   /(?<![^\s>|])![<=>]?(?:\([^")\n]+\)|\{[^{"}\n][^"}\n]+\}|\[[a-z_-]+\])*[^\s(!]*[.\/][^\s(!]*(?:[ \t]?\((?:[^()\n]|\([^()\n]+\))+\))?!/
   ```

   - The opening `!` counts only at the start of the text, after whitespace,
     `>` or `|` — the positions where Textile itself starts an image.
   - The attribute block accepts alignment (`<`, `=`, `>`), class/id
     parentheses, style braces, and language brackets in any order and
     number, with whitespace allowed inside (`width: 794px`, `my cls`).
   - The alternative text accepts spaces and one level of nested parentheses
     after up to one space, on a single line.
   - The file name or URL must contain `.` or `/` and no whitespace, `(` or
     `!`, which keeps `!wow!`-style emphasis from matching.
   - Unlike RedCloth, which reads the three attribute kinds in three fixed
     orders, the pattern allows any order and any count; see point 2. Unlike
   RedCloth's `IMAGE_RE`, the pattern does not include the "dot plus space"
   branch (`!{width: 1px}. a.png!`): measured against Redmine, Textile does
   not render that shape as an image, and including it was the only
   over-detection of the first candidate.

2. **Repeating an attribute kind is accepted as over-detection.**
   `!(a)(b)c.png!` and `!{a: b}{c: d}e.png!` count (3 points) although Textile
   renders neither as an image. Listing RedCloth's three fixed orders instead
   would triple the expression's length for a shape that needs two stacked
   attributes plus a dotted file name plus a boundary-respecting `!` — rare
   in ordinary prose. Pinned in contract C-4.

3. **Some shapes the current pattern counts stop counting**, matching
   Textile, which never renders them as images:

   | Input | Textile `<img>` | Old pattern | New pattern |
   |---|---|---|---|
   | `x!a.png!`, `これは!a.png!`, `x.!a.png!`, `x:!a.png!` | no | matches | no match |
   | `(!a.png!)`, `「!a.png!」`, `"!a.png!"`, `*!a.png!*` | no | matches | no match |
   | `すごい!(笑)次はa.png!` | no | matches | no match |
   | `!a(b).png!`, `!https://ex.com/a_(b).png!` | no | matches | no match |
   | `` `!{width: 794px}.a.png!` `` (inline code) | — | 3:3 undecided | 0:3 CommonMark |

   A file name holding `(` is read by RedCloth as the start of alternative
   text, so it produces no image and does not count. Inline code now leans
   Markdown (0:3) because the notation stops matching while the backtick
   still scores for CommonMark. Documents whose only image evidence is such a
   shape follow the site setting from now on; Textile would not have shown an
   image for them either, so nothing breaks visually.

`Detector::VERSION` goes from 6 to 7 in the same change, because verdicts
move and the formatted-HTML cache must not serve HTML rendered before it
([ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md)).

## Alternatives considered

- **The issue #15 proposal, `/!(?:\{[^}\n]*\})?\S*[.\/]\S*!/`.** Rejected: it
  covers only the pasted shape with a style block. It misses alignment
  (`!>…`), class/id blocks, language brackets, and alternative text with
  spaces (`!a.png(alt text)!`), and it has no condition on what precedes the
  opening `!`, so `x!a.png!` keeps counting although Textile renders no
  image.
- **Add only a `{…}` branch to the current pattern.** Rejected for the same
  reasons: it patches one symptom while the rest of the pattern still
  disagrees with Textile about where an image starts and ends.
- **Drop the preceding-character condition.** Rejected: every `!` next to a
  `{` or `(` in running prose — `Wow!{a b} c.d!`, `Hi!(see x.y) ok!`,
  `Error!(code) x.rb!` — would score for Textile, switching Markdown
  documents for no reason.

## Consequences

- **Pasted images render on Markdown sites.** A body of
  `!{width: 794px}.clipboard-….png!` scores 3:0 and reads as Textile, so the
  image shows under either site setting.
- **Markdown documents with look-alike punctuation stay Markdown.** `!`
  followed by `{` or `(` in ordinary sentences scores nothing, and the
  boundary condition keeps notation glued to a word (`x!a.png!`) from
  counting.
- **Some former matches are no longer counted**, as listed under Decision 3.
  A document whose Textile evidence was only such a shape becomes
  undecided (`no_signal`) and follows the site setting; Textile rendered no
  image for it anyway.
- **Repeated attributes of one kind count without an image** (Decision 2);
  the shape is contrived and pinned as accepted over-detection.
- **Two-line alternative text is missed** (`!a.png(alt\ntext)!`): Textile
  renders it as an image, the pattern does not match across lines. It follows
  the site setting unless other evidence decides.
- **A Markdown image whose alternative text ends in `!` may still count**,
  as in `![a.png](a.png)!`, but the Markdown pattern already scores 4 points
  for the same text, so the verdict does not move. The new pattern is
  strictly narrower here than the old one.
- **Re-verify when Redmine updates its formatters:** that Textile still
  renders `!…!` with attribute blocks as images at these boundaries, that the
  style/class/language attribute grammar of RedCloth is unchanged, and that
  CommonMark still leaves the notation as plain text.
