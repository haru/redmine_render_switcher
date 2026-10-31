# ADR-0006: Score Textile insertion notation (`+text+`) where Textile renders it

- **Status**: Accepted
- **Date**: 2026-10-31

## Context

[ADR-0005](./0005-score-only-notation-that-renders-differently.md) left `+ins+` out
of the scoring tables as too rare to be worth a pattern. A real document has since
shown that the notation can be the only evidence a Textile document carries.

The description of [redmine.tokyo issue #1755](https://redmine.tokyo/issues/1755) is a
filled-in template: labels written as `+*label:*+`, with plain prose between them.
Measured against Redmine 7.0.1-stable with the default threshold of 2:

| Measurement | Result |
|---|---|
| Score | Textile 0 : Markdown 0 (`no_signal`) |
| Rendered as Textile | `<ins><strong>label:</strong></ins>` |
| Rendered as Markdown | `+<em>label:</em>+` |

The notation passes the test in decision 1 of ADR-0005: Textile renders it as markup
and CommonMark leaves the plus signs as plain text. Only the rarity argument kept it
out. That argument is weak where the plugin matters most: the main deployment sets the
site format to Markdown, so a Textile document with no detected evidence falls back to
Markdown and shows stray plus signs.

The plus sign also appears in plenty of ordinary text, so where the notation counts
was measured by comparing a candidate rule with Textile's output on about 70 inputs.
The conclusions are restated here; the full table is in
`specs/003-detect-textile-insertion/spec.md` (local to the maintainers, not committed).

## Decision

1. **`+text+` scores for Textile, at 3 points per occurrence**, the weight inline code
   has in both tables. One occurrence is enough, so with no other evidence it decides
   the text. Nested notation such as `+*text*+` counts the same.
2. **It counts in the positions where Textile renders it as an insertion, apart from
   the residual cases under Consequences.**
   - The opening `+` follows the start of a line, whitespace or `(`. It may also follow
     a `*` that starts a line or follows whitespace (strong text), or a `|` that starts
     a line (a table cell). `x*+ab+*y` and `x |+ab+| y` render no insertion and do not
     count.
   - The closing `+` precedes the end of a line, whitespace, or one of `.` `,` `;` `:`
     `!` `?` `)` `*` `|` `。` `、` `）`.
   - The content does not begin or end with whitespace and stays on one line.
   - The content is at least two characters long, so `+a+` and `+1+` score nothing.
3. **Code blocks stay masked.** A `+text+` inside a fence, `<pre>` or an indented block
   scores nothing, like any other notation.
4. **The rest of the rarity decision in ADR-0005 stands.** `-del-`, `%span%`, `??cite??`,
   `fn1.`, `~~strike~~`, the `+ ` bullet and the `N) ` list stay unscored.

`Detector::VERSION` goes from 5 to 6, because the change moves verdicts and the
formatted-HTML cache must not serve HTML rendered before it
([ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md)).

## Alternatives considered

- **Keep the notation unscored and rely on the directive.** Rejected: every affected
  document would need an edit, which is the migration work the plugin exists to avoid.
- **Guard only against word characters, as Textile inline code does.** Rejected: it
  also matches `これは+下線+です`, `C++/C++`, `` `+ins+` ``, `[+ins+](url)`, `=+ins+` and
  `?q=+a+`, none of which Textile renders as an insertion. Each match could switch a
  Markdown document for no reason.
- **Require two or more occurrences.** Rejected: a Textile document with one underlined
  phrase would keep showing plus signs on a Markdown site, and that notation is written
  on purpose. Inline code has no such floor either.
- **Count single-character content too.** Rejected: `x = +a+ b` and `+1+` look like
  arithmetic or variables far more than underlining.
- **Score once per document or block, following decision 3 of ADR-0005.** Rejected:
  inline notation has no block to count, and both inline code patterns already score
  per occurrence. The notation follows them, so its evidence grows with its count.
- **Use a lower weight.** Rejected: a weight of 1 would no longer decide a document at
  the default threshold of 2, and 3 matches the weight of inline code.

## Consequences

- **Plain prose can read as Textile.** A text whose only notation is `Ctrl +Alt+ Del` is
  read as Textile, which really does render it as an insertion. The detector judges the
  notation a text uses, not what its author meant.
- **One occurrence does not outweigh other Markdown evidence.** With a dash list it scores
  3:3 and with a Markdown link 3:4. Both stay undecided and follow the site setting.
- **Single-character insertions are missed**, as in `+字+` or `+a+`, even though Textile
  renders them. With no other evidence they follow the site setting.
- **Some real insertions are missed.** `_+ins+_`, `++x++`, `+++x+++`, `+ins+/x`, `+ins+-x`,
  `+ins+'s` and a `+text+` spanning two lines render as insertions but score nothing.
  They follow the site setting unless other evidence decides.
- **Content holding a plus sign is missed too**, as in `+ab+cd+` and `+ab + cd+`, which
  Textile renders as insertions, and so are plus signs at the edge of the content
  (`+C++ and Java`, `++ab+ x`, `x +ab++ y`). Allowing a plus sign in the content would
  make `++x++` match.
- **Table cells after the first are missed.** `|a|+ins+|` renders an insertion, but only
  a pipe at the start of a line counts as an opener.
- **Inline code is not masked, so spaced notation inside it counts.** One occurrence in
  Markdown inline code, as in `` `a +bc+ d` ``, scores 3:3 and stays undecided. Two in
  the same span, as in `` `a +bc+ d +ef+ g` ``, score 6:3 and switch a Markdown text to
  Textile. Masking inline code would add a removal rule beyond code blocks for a rare
  shape; the directive corrects an affected text.
- **Some text Textile leaves alone still counts.** `<code> +ins+ </code>`,
  `<notextile> +ins+ </notextile>`, an HTML comment such as `<!-- +abc+ -->` and a
  lone leading pipe as in `|+ins+` render no insertion but score 3:0, so with no other
  evidence they read as Textile. Whether a `|` opens a table cell depends on the whole
  line, which a lookbehind cannot see.
- **Unfenced diffs can switch.** Textile renders `+foo bar+` as an insertion, so a
  unified diff pasted without a fence, with an added line such as `+y = a+`, scores 3:0
  and reads as Textile. A diff inside a fence or an indented block is masked and
  unaffected.
- **An underline can outweigh Setext headings.** The `-` underline is unscored, so a
  Markdown page headed `A` / `---` that also holds `+ab+` scores 3:0, reads as Textile
  and has no sections, where without the underline it keeps two. The rendered headings
  and the source numbering agree about that, so a section save stays safe; the
  directive corrects an affected page. Pinned in
  `test/integration/render_switcher_section_edit_test.rb`.
- **Text attached to CJK characters scores nothing**, as in `これは+下線+です`, because
  Textile does not render it as an insertion either. The same goes for a full-width
  space on either side (`x +ab+　y`).
- **Re-verify when Redmine updates its formatters:** that Textile still renders `+text+`
  as an insertion at these boundaries, and that CommonMark still leaves it as plain text.
