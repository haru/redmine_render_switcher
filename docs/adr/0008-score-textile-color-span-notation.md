# ADR-0008: Score Textile color span notation (`%{color:red}text%`)

- **Status**: Accepted
- **Date**: 2026-11-27

## Context

Redmine's Textile format renders `%{color:red}NG%` as
`<span style="color:red;">NG</span>`, while CommonMark leaves the characters
untouched. A site that switched its setting from Textile to Markdown therefore
shows every existing color span as raw notation, and the detector, which has no
pattern for the shape, renders those bodies as Markdown itself. The reporter of
issue #16 compared Textile-fixed HTML against plugin-rendered HTML over
256,957 production texts: 39,633 changed structurally, and **4,541** of them
were caused by color spans alone — the largest single named cause in the
report.

This ADR complements [ADR-0005](./0005-score-only-notation-that-renders-differently.md),
[ADR-0006](./0006-score-textile-insertion-notation.md) and
[ADR-0007](./0007-score-styled-textile-image-notation.md) (none superseded) and
follows their method: a candidate rule was compared against Textile's actual
output, produced by Redmine 7.0.1-stable with RedCloth, over the spec's
background table (31 inputs) plus 14 further edge cases, with zero
disagreements. `scan` over pathological inputs stays in the same range as
RedCloth's own rendering of the same input (34 ms against 76 ms per 10,000
one-line occurrences), because the lazy body repeats RedCloth's own `.*?`
behaviour. The evidence lives in `specs/007-detect-textile-color-span/research.md`.

## Decision

1. **The span notation counts as Textile evidence** because it meets the
   ADR-0005 criterion: Textile renders `<span style="color:…">` from it and
   CommonMark leaves the characters as plain text, so the two formats render
   the same characters differently and a reader sees the difference.

2. **Only a `color` property counts**, encoded as the `TEXTILE_COLOR_SPAN`
   constant and registered in `TEXTILE_PATTERNS` at weight 3:

   ```ruby
   TEXTILE_COLOR_SPAN = /
     (?<=^|[\s(>|]) \*{0,2}
     %
     \{ (?:(?!\{)[^"}\n]*;)? [ \t]* color: [^"}\n]* \}
     (?: [^\n] | \n(?![ \t\r]*$) )*? \S
     %
     (?=$|\s|[[:punct:]])
   /xi
   ```

   A `color` property is a name that is exactly `color` (case-insensitive),
   followed immediately by `:`, placed right after `{` or after a `;`-ended
   property (whitespace allowed in between). Mixed blocks count
   (`%{font-weight:bold; color:red}x% y`), `background-color` and
   `border-color` do not (the name is not `color`), `color :red` does not
   (Redmine throws the style away and renders a bare `<span>`), and a block
   without a colon at all (`%{count}`, the shape of Ruby i18n format strings)
   does not.

   **Why `color` only:** issue #16 carries occurrence counts for color spans
   alone; no data exists for `background`, `font-size`, `background-color` or
   any other property, and YAGNI (constitution VI) forbids scoring shapes
   nobody has measured. The cost is accepted recall loss: bodies decorated
   only with other properties stay undecided and keep rendering as Markdown,
   where the decoration is lost. When counts for another property appear, a
   follow-up can extend the rule with its own data.

3. **The boundaries follow RedCloth's `QTAGS` `:limit` rules**
   (`redcloth3.rb`), so the pattern counts only the positions Textile really
   renders a span: the opener sits at the start of a line or after whitespace,
   `(`, `>` or `|` (the `|` being the same table-cell approximation
   ADR-0007 makes), optionally preceded by up to two `*` (bold/strong around a
   span); the body is non-empty, stays within its paragraph (no blank line) and
   does not end with whitespace; the closer is followed by end of line,
   whitespace or a punctuation character, which is `[[:punct:]]` because
   RedCloth itself tests punctuation that way — full-width Japanese punctuation
   (`、` `。` `！` `）` `」`) matches it too. The body is matched lazily, so
   `結果は %{color:red}NG%でした。次は 50% です` closes at the later valid `%`
   exactly as RedCloth does. The paragraph limit holds for CRLF line breaks
   too, which is how Redmine stores issue descriptions. The pattern is
   ASCII-only and fixes no encoding, so it adds no encoding constraint of its
   own; the full-width punctuation above matches in a UTF-8 string, and
   invalid byte sequences still raise, as they should.

   The remaining gaps are pinned by the detector test's fixtures
   (`COLOR_SPAN_MISSED`, `COLOR_SPAN_RESIDUAL`, and for the two rows noted
   below `COLOR_SPAN_NOT_COLORED` and `COLOR_SPAN_COUNTED`) so that a later
   change cannot widen or close them unnoticed:

   | Input | Textile renders | Pattern | Reason |
   |---|---|---|---|
   | `%{color:red}a` ⏎ `%` | colored span (`<br>` inside) | no match | body ends at a newline, which is whitespace (FR-003) |
   | `%(cls){color:red}x% y` | colored span | no match | class attribute before the style is out of scope |
   | `_%{color:red}x%_`, `-%{color:red}x%-` | colored span | no match | only `*`/`**` prefaces count; no data for other emphasis |
   | `***%{color:red}x%*** y` | colored span | no match | up to two stars only; three are out of scope |
   | `%{color:\nred}x%` (in `COLOR_SPAN_NOT_COLORED`) | bare `<span>` | no match | multi-line `{…}`; Textile drops the style too, so nothing is lost |
   | `a\|%{color:red}x% y` | plain text | match | a `|` that is not a table cell (decision 3's approximation) |
   | `%{color:rgb(1,2,3)}x% y`, `%{color:}x% y` | bare `<span>` | match | value fails Redmine's `STYLES_RE`, style dropped — the notation still disappears from the page |
   | `` `a %{color:red}NG% b` `` (in `COLOR_SPAN_COUNTED`) | colored span, backticks kept as text | match | a backtick is not code in Textile, so the span after the space renders; inline code is outside code-block masking, the Markdown backticks score 3 in return and the document ties |

4. **The weight is 3 points**, the same as the other inline notations
   (`TEXTILE_INLINE_CODE`, `TEXTILE_INSERTION`, `TEXTILE_IMAGE`): one
   occurrence alone clears the default threshold of 2, which is what saves a
   document whose only Textile evidence is one color span — the majority shape
   in the reporter's data.

`Detector::VERSION` goes from 7 to 8 in the same change, because verdicts move
and the formatted-HTML cache must not serve HTML rendered before it
([ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md)); the
cache-key suffix becomes `-rs8t<threshold>`.

## Alternatives considered

- **Score any `{…}` holding a colon** (`%{count}` included). Rejected at
  clarification: Ruby i18n format strings such as `件数は %{count}件% です`
  appear in ordinary Markdown prose and would flip documents for no visible
  gain — Textile renders such a block as a bare `<span>` with no decoration.
- **A loose property match, `\bcolor\s*:`.** Rejected: it matches
  `background-color` (whose style Redmine keeps, so spans would count without
  a color) and `color :red` (whose style Redmine throws away).
- **A negated lookbehind for the opener, `(?<![^\s(>|*])`.** Rejected: it
  admits `a*%{color:red}x%*`, which Textile does not render as a span. The
  `*` prefix has to be "one or two stars after a valid position", hence the
  separate `\*{0,2}`.
- **Score other styled properties (`background`, `font-size`, …) too.**
  Deferred, not rejected: no occurrence data exists for them (issue #16
  measured color only). Revisit when data arrives.

## Consequences

- **Existing color spans render colored on Markdown sites.** A body of
  `結果は %{color:red}NG% でした` scores 3:0 and reads as Textile, so the
  span renders under either site setting.
- **Ordinary `%` prose stays Markdown.** `達成率 50% と 80% の間`,
  `結果は%{color:red}NG%でした` (no boundary on either `%`),
  `%{background:yellow}黄% x` and `件数は %{count}件% です` score nothing.
  The first two are pinned by `COLOR_SPAN_NOT_NOTATION` (Textile renders no
  span at all); the last two by `COLOR_SPAN_NOT_COLORED` (Textile renders a
  bare, undecorated `<span>`). RedCloth renders none of them as a colored
  span.
- **Some Textile spans are missed**, as listed under Decision 3; a body whose
  only evidence is such a shape stays undecided and follows the site setting.
- **A few shapes count although Textile renders no colored span** (a `|` that
  is not a table cell, a value `STYLES_RE` rejects); each is contrived and
  pinned as accepted over-detection. The spaced inline-code case renders a
  colored span in Textile after all — a backtick is not code there — and
  merely ties 3:3 with the Markdown backticks, so its verdict does not move.
- **Cached HTML rendered before this change is invalidated** by the version
  bump; the first render after upgrading recomputes it.
- **Re-verify when Redmine updates its formatters:** that Textile still
  renders `%{…}…%` as a styled span at these boundaries, that `QTAGS`'s
  `:limit` rules and `STYLES_RE` are unchanged, and that CommonMark still
  leaves the notation as plain text.
