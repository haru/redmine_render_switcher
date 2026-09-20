# ADR-0005: Score only notation that renders differently, one score per block, precision before recall

- **Status**: Accepted
- **Date**: 2026-09-19

## Context

The detector's scoring tables were written on the rule "notation that only one
format gives meaning to". Measured against Redmine 7.0.1-stable, that rule let a
wrong entry in and kept real evidence out.

- **`**bold**` was scored for Markdown, and both formats render it as bold.**
  Textile produces `<b>`, CommonMark produces `<strong>`; a reader sees the same
  thing. Worse, the notation next to it flips meaning: `*change*` is bold in Textile
  and emphasis in Markdown. A Textile document that used `**` for bold and `*` for
  emphasis was therefore pulled to Markdown on the strength of a notation that
  carries no information, and the `*` in the same text then rendered the wrong way
  round.
- **The most common document shapes gave no signal at all.** Dash and numbered
  lists, Setext headings (`Title` over a line of `=`) and Textile tables without a
  separator row are all read by one format and left as plain text by the other, yet
  the tables had no entry for any of them.
- **An indented code block could decide the format.** A Textile snippet quoted after
  a blank line, indented by four spaces, scored like live Textile.

The failure modes are not symmetric between the two formats. They are asymmetric
between *switching* and *not switching*. A wrong switch changes how a document
renders. A missed detection only leaves the site setting in charge, which is the
behaviour of a Redmine without the plugin.

The measurements behind this are recorded in `specs/002-fix-detector-rules/research.md`
(local to the maintainers, not committed); the conclusions are restated here.

## Decision

1. **A notation is scored only if one format renders it as markup and the other
   leaves it as plain text, or if the two render it differently enough that a reader
   would notice.** Notation both formats render with the same meaning is not scored,
   even where the HTML tag names differ. `**bold**` is therefore removed. `_em_`,
   `> quote`, `* item` and `---` stay out for the same reason.
2. **Precision comes before recall, on both sides.** A rule that could cause a wrong
   switch is not adopted, even at the price of missing documents it could have
   caught. Where a document is genuinely ambiguous the result is "undecided" and the
   site setting decides.
3. **New rules score once per block, not once per line.** A list or a table adds
   one fixed score however many lines it spans, and a Setext heading adds one fixed
   score per heading (see Consequences for why that is not once per document). Scored
   per line,
   the evidence would grow with the length of the block. A Textile document with
   `h1. Notes` followed by five hand-written dash lines scores 5:10 at two points per
   line and flips to Markdown; scored once per block at three points it scores 5:3
   and stays Textile, whether the dashes run two lines or fifty.
4. **A list needs at least two consecutive lines.** A dash at the start of a line is
   also how prose breaks off an aside, and Markdown does render such a line as a
   list. Requiring two lines resolves this the same way a table already does (two
   consecutive rows), instead of letting ordinary prose count as Markdown.

The rules this yields:

| Notation | Evidence for | Score |
|---|---|---|
| `- ` or `N. ` lines, two or more in a row (blank lines do not end the block) | Markdown | 3 per block |
| A line of `=` under a line of text (Setext heading) | Markdown | 4 each |
| Pipe-delimited rows, two or more, no separator row | Textile | 4 per block |
| Pipe-delimited rows including a separator row | Markdown | 5 per block |

A separator row is a row made of nothing but pipes, hyphens, colons and spaces, with
at least one hyphen. A row that only starts like one, such as `| - | x |`, is a
Textile row with a dash for a cell.

An indented block (four spaces or a tab) that follows a blank line is masked out of
scoring like a fence or a `<pre>`. It is not masked when the last non-blank line
above it is a list item (`-`, `*` or `N.`), blank lines in between or not, because
the indent is then a continuation and not code. A `#` line is not a list item for
this purpose: a heading takes no continuation, so an indented block under one is
code.

`Detector::VERSION` goes from 3 to 4, because the change moves verdicts and the
formatted-HTML cache must not serve HTML rendered before it
([ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md)).

## Alternatives considered

- **Keep the old test, "notation only one format gives meaning to".** It is the rule
  that admitted `**bold**`. It says nothing about notation both formats give
  *different* meanings, which is where the harm is done.
- **Leave `**bold**` scored.** Rejected: it keeps flipping Textile documents whose
  only Markdown-looking notation is bold.
- **Demote `**bold**` to weak evidence instead of removing it.** The score follows the
  number of occurrences, so a document with two bold words would still reach the
  threshold. Making it work needs a weight that ignores counts, which is more
  machinery than the notation is worth.
- **Score per line.** Fails decision 3 in the worst case above. Scoring one point per
  line does not flip that document, but it leaves the length dependence in place and
  removes the margin for longer lists.
- **Score a single dash line.** Ordinary prose is then read as Markdown, which
  switches documents on the Textile-site setup.

## Consequences

- **A document with only one dash line is missed** and follows the site setting. The
  original requirement asked for dash lists to count; the two-line floor makes that
  slightly narrower than it read.
- **A document whose only notation is `**` and `*` follows the site setting.** Under
  a Textile site this renders as Textile (`<b>`, `<strong>`), under a Markdown site
  as Markdown (`<strong>`, `<em>`), which is the correct fallback.
- **A Textile document that puts lines of `=` under text can lose its verdict, and
  with enough of them can flip.** Each such line scores 4 for Markdown and, unlike a
  list, is not scored once per block. Measured: `h1. Title` with one such line is
  5:4 (undecided); with two it is 5:8 and is read as Markdown. This is the one place
  where the per-block rule of decision 3 does not apply, and it is accepted because
  Textile has no reason to underline text with `=`. If real documents show
  otherwise, the fix is to score Setext headings once per document, which needs a new
  `Detector::VERSION`.
- **The `-` Setext underline is not scored**, because `---` is also the horizontal
  rule that both formats render alike, and a line of dashes alone does not say which
  it is.
- **A Textile table row that holds only dashes still counts as a separator row.** A
  placeholder row such as `| - | - |` has the shape of a Markdown separator, and the
  rule does not check where in the table it sits (a lone `|---|` is Markdown
  evidence on purpose). Such a table scores for Markdown and, with a `|_.` header
  row, ends level at 5:5 and undecided. Checking that the separator is the second
  row would close it, at the price of the lone-separator case.
- **Notation deliberately left out**, so that later proposals do not repeat the
  analysis: `ABBR(text)` (it matches `GET(path)`), `p. ` (it matches `p. s.`),
  `-del-`, `+ins+`, `%span%`, `??cite??`, `fn1.` and `~~strike~~` (too rare, and
  none is added for either format), Markdown reference and auto links, and the `+ `
  bullet and `N) ` numbered list, which only Markdown renders as lists but fall to
  the same rarity test.
- **A document that begins with an indented line is scored as usual.** No blank line
  above it opens a code block, so a quoted snippet at the very start of a text is
  not masked. It is a known limit that is deliberately left as it is.
- **Re-verify when Redmine updates its formatters:** that `**bold**` still renders
  as bold in both, that `*x*` still differs between them, and how each treats a
  four-space indent.
