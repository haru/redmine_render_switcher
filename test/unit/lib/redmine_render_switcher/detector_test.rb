# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherDetectorTest < ActiveSupport::TestCase
  TEXTILE_TYPICAL = <<~'TEXT'
    h1. Release procedure

    See "the official site":https://redmine.org/ for the details.

    bq. Quote the release manager here.

    |_. Item |_. Value |
    | Name | Redmine |

    Read @Setting.text_formatting@ to find the format.

    !https://example.com/logo.png!
  TEXT

  MARKDOWN_TYPICAL = <<~'TEXT'
    # Release procedure

    See [the official site](https://redmine.org/) for the details.

    > Quote the release manager here.

    | Item | Value |
    | --- | --- |
    | Name | Redmine |

    Read `Setting.text_formatting` to find the format.

    ![logo](https://example.com/logo.png)

    ```ruby
    puts "hello"
    ```
  TEXT

  # Deliberately non-ASCII, and kept that way: CJK prose runs without spaces
  # between words, which makes it the text most likely to trip a pattern that
  # leans on whitespace boundaries. The detector must still find no signal in it.
  PLAIN_NON_ASCII_PROSE = "これは普通の日本語の文章です。記法の特徴はありません。\n"

  # Also deliberately non-ASCII: the pattern tables have to recognise notation
  # that wraps multibyte content, not only ASCII. One case per format is enough,
  # so every other fixture here is written in English.
  NON_ASCII_TEXTILE = <<~'TEXT'
    h2. 見出し

    "リンク":https://ex.com/
  TEXT

  NON_ASCII_MARKDOWN = <<~'TEXT'
    ## 見出し

    [リンク](https://ex.com/)
  TEXT

  TEXTILE_SHORT = <<~'TEXT'
    h2. Heading

    "link":https://ex.com/
  TEXT

  MARKDOWN_SHORT = <<~'TEXT'
    ## Heading

    [link](https://ex.com/)
  TEXT

  TEXTILE_ORDERED_LIST = <<~'TEXT'
    # Start the server
    # Configure it
    # Verify the result
  TEXT

  TEXTILE_NESTED_ORDERED_LIST = <<~'TEXT'
    # Prepare
    ## Gather the materials
    ## Reserve the room
    # Execute
  TEXT

  MARKDOWN_H1_ONLY = <<~'TEXT'
    # Title

    Body text.
  TEXT

  MARKDOWN_H1_AND_H2 = <<~'TEXT'
    # Title

    ## Section

    Body text.
  TEXT

  MARKDOWN_MANY_HEADINGS = <<~'TEXT'
    # Title

    ## Section 1

    Body text.

    ## Section 2

    Body text.

    ### Subsection

    Body text.
  TEXT

  URL_ONLY = "https://example.com/path/to/page\n"

  SHARED_SYNTAX_ONLY = <<~'TEXT'
    * apple
    * orange

    > quoted line
  TEXT

  TEXTILE_WITH_MARKDOWN_IN_PRE = <<~'TEXT'
    h2. Sample

    <pre>
    [link](https://ex.com/)
    **bold**
    </pre>

    "reference":https://ex.com/
  TEXT

  MARKDOWN_WITH_TEXTILE_IN_FENCE = <<~'TEXT'
    ## Sample

    ```
    h1. this line is textile
    "link":https://ex.com/
    ```

    [reference](https://ex.com/)
  TEXT

  # Redmine renders @login as a user mention and a@b.com as a mailto link. Neither
  # is Textile inline code, but the inline-code pattern used to run greedily from
  # one @ to the next and swallow a pair of them, which pushed a Markdown page far
  # enough towards Textile to lose the margin.
  #
  # The Markdown evidence is a two-line dash list.
  MARKDOWN_WITH_MENTIONS = <<~'TEXT'
    Thanks @alice and @bob for the review.

    - reviewed
    - approved
  TEXT

  MARKDOWN_WITH_EMAILS = <<~'TEXT'
    Contact a@example.com or c@example.com.

    See [the guide](https://ex.com/) first.
  TEXT

  TEXTILE_INLINE_CODE_WITH_SPACES = <<~'TEXT'
    h2. Usage

    Run @rake db:migrate@ in the terminal.
  TEXT

  # Lines whose Textile inline-code verdict is pinned against RedCloth itself, so
  # that tightening or loosening the pattern cannot drift away from what Textile
  # actually renders.
  INLINE_CODE_GROUND_TRUTH = [
    "Thanks @alice and @bob for the review.",
    "Contact a@example.com or c@example.com.",
    "cc @alice and mail x@example.com",
    "Run @rake db:migrate@ in the terminal.",
    "Read @Setting.text_formatting@ for it.",
    "Use the @x@ variable here.",
    "Wrap it in parens (@code@) like so."
  ].freeze

  # Textile 4 (+bq.+) against Markdown 3 (inline code): a margin of one.
  NARROW_MARGIN = <<~'TEXT'
    bq. quoted line

    Run `config` first.
  TEXT

  # One notation from each side, weighted the same, so the two scores land level.
  EXACT_TIE = <<~'TEXT'
    Read @Setting.text_formatting@ for it.

    Run `config` first.
  TEXT

  MIXED_AND_CLOSE = <<~'TEXT'
    h2. Textile heading

    "link":https://ex.com/

    ## Markdown heading

    [link](https://ex.com/)
  TEXT

  # A loose list: Markdown still reads the blank lines as one list.
  LOOSE_DASH_LIST = <<~'TEXT'
    - one

    - two

    - three
  TEXT

  # A single dash line in prose is not a list.
  LONE_DASH_LINE = <<~'TEXT'
    Costs are stable.
    - see the note below

    That is all.
  TEXT

  # Two lists that a paragraph of prose separates: two blocks, so two scores.
  TWO_SEPARATE_LISTS = <<~'TEXT'
    - a
    - b

    Some prose here.

    - c
    - d
  TEXT

  # Textile notation quoted in an indented code block, between two paragraphs.
  INDENTED_TEXTILE_LINK = <<~'TEXT'
    Intro paragraph.

        "link":https://ex.com/

    End paragraph.
  TEXT

  # An indented block with a blank line in the middle of it.
  INDENTED_BLOCK_WITH_BLANK_LINE = <<~'TEXT'
    Intro paragraph.

        first

        "link":https://ex.com/

    End paragraph.
  TEXT

  # A list item followed by two indented continuation paragraphs, one blank line
  # apart.
  LIST_WITH_TWO_INDENTED_CONTINUATIONS = <<~'TEXT'
    - item

        still the item, part one

        "link":https://ex.com/
  TEXT

  # A Markdown table, a blank line, then a bare Textile table.
  MIXED_TABLES = <<~'TEXT'
    | Name | Value |
    | --- | --- |
    | a | 1 |

    | x | y |
    | z | 2 |
  TEXT

  # Both formats render +**bold**+ as bold, and +*change*+ means bold in Textile but
  # emphasis in Markdown. Neither says which format the author wrote, so there is
  # nothing to score and the site setting decides.
  BOLD_AND_EMPHASIS_ONLY = <<~'TEXT'
    This is an **important** *change*.
  TEXT

  # The +**+ must not add to the Markdown side, so the heading alone decides.
  TEXTILE_HEADING_WITH_DOUBLE_STAR_BOLD = <<~'TEXT'
    h1. Heading

    This is **bold**.
  TEXT

  # Each row is one detection case: input text, expected format, expected reason.
  # This table is the case set SC-002 refers to; every row must match, and a new
  # row is added before the fix whenever a misdetection is found.
  CASES = [
    { id: "D-01", text: TEXTILE_TYPICAL, format: "textile", reason: :score },
    { id: "D-02", text: MARKDOWN_TYPICAL, format: "common_mark", reason: :score },
    { id: "D-03", text: PLAIN_NON_ASCII_PROSE, format: nil, reason: :no_signal },
    { id: "D-04", text: TEXTILE_SHORT, format: "textile", reason: :score },
    { id: "D-05", text: MARKDOWN_SHORT, format: "common_mark", reason: :score },
    { id: "D-06", text: TEXTILE_ORDERED_LIST, format: "textile", reason: :score },
    { id: "D-07", text: TEXTILE_NESTED_ORDERED_LIST, format: "textile", reason: :score },
    { id: "D-08", text: MARKDOWN_H1_ONLY, format: "common_mark", reason: :score },
    { id: "D-09", text: MARKDOWN_H1_AND_H2, format: "common_mark", reason: :score },
    { id: "D-10", text: MARKDOWN_MANY_HEADINGS, format: "common_mark", reason: :score },
    { id: "D-11", text: "", format: nil, reason: :no_signal },
    { id: "D-12", text: URL_ONLY, format: nil, reason: :no_signal },
    { id: "D-13", text: SHARED_SYNTAX_ONLY, format: nil, reason: :no_signal },
    { id: "D-14", text: TEXTILE_WITH_MARKDOWN_IN_PRE, format: "textile", reason: :score },
    { id: "D-14b", text: MARKDOWN_WITH_TEXTILE_IN_FENCE, format: "common_mark", reason: :score },
    { id: "D-15", text: NARROW_MARGIN, format: nil, reason: :below_threshold },
    { id: "D-16", text: MIXED_AND_CLOSE, format: nil, reason: :below_threshold },
    { id: "D-17", text: MARKDOWN_WITH_MENTIONS, format: "common_mark", reason: :score },
    { id: "D-18", text: MARKDOWN_WITH_EMAILS, format: "common_mark", reason: :score },
    { id: "D-19", text: TEXTILE_INLINE_CODE_WITH_SPACES, format: "textile", reason: :score },
    { id: "D-20", text: NON_ASCII_TEXTILE, format: "textile", reason: :score },
    { id: "D-21", text: NON_ASCII_MARKDOWN, format: "common_mark", reason: :score },
    { id: "D-22", text: BOLD_AND_EMPHASIS_ONLY, format: nil, reason: :no_signal },
    { id: "D-23", text: TEXTILE_HEADING_WITH_DOUBLE_STAR_BOLD, format: "textile", reason: :score },
    # Lists: only Markdown reads a dash or a "1." at the start of a line as a list.
    { id: "D-24", text: "- faster\n- fewer queries\n", format: "common_mark", reason: :score },
    { id: "D-25", text: "1. stop the server\n2. migrate the data\n", format: "common_mark", reason: :score },
    { id: "D-26", text: "* apple\n* orange\n", format: nil, reason: :no_signal },
    { id: "D-27", text: LOOSE_DASH_LIST, format: "common_mark", reason: :score },
    { id: "D-28", text: "7. seventh\n8. eighth\n", format: "common_mark", reason: :score },
    # Setext headings, and the contexts in which an underline is not one.
    { id: "D-29", text: "Release notes\n=============\n", format: "common_mark", reason: :score },
    { id: "D-30", text: "=====\nSome text.\n", format: nil, reason: :no_signal },
    { id: "D-31", text: "Intro text.\n\n=====\n", format: nil, reason: :no_signal },
    { id: "D-32", text: "- item\n=====\n", format: nil, reason: :no_signal },
    # Prose that merely looks like markup must stay undecided.
    { id: "D-33", text: "We run 10-20 workers - or fewer - per host.\n", format: nil, reason: :no_signal },
    { id: "D-34", text: LONE_DASH_LINE, format: nil, reason: :no_signal },
    { id: "D-35", text: "See step 3.\n1. that one\n", format: nil, reason: :no_signal },
    { id: "D-36", text: "Call GET(path) and expect 50% +/- 2 of the rows.\n", format: nil, reason: :no_signal },
    { id: "D-37", text: "Nothing here uses any markup at all.\n", format: nil, reason: :no_signal },
    # Accepted change: the Setext underline now counts for Markdown, which pulls this
    # Textile document from a clear win to a near tie (5:4). With the default
    # threshold and a single underline it falls on the side that switches to neither
    # format, so the site setting decides. A second underline does flip it to
    # Markdown, which is pinned below and recorded in ADR-0005.
    { id: "D-38", text: "h1. Title\n\nRelease notes\n=====\n", format: nil, reason: :below_threshold },
    # Tables: a run of pipe-delimited rows is Textile unless a separator row makes
    # it a Markdown table.
    { id: "D-39", text: "| Name | Value |\n| a | 1 |\n", format: "textile", reason: :score },
    { id: "D-40", text: "| Name | Value |\n|---|---|\n| a | 1 |\n", format: "common_mark", reason: :score },
    { id: "D-41", text: "| Name | Value |\n", format: nil, reason: :no_signal },
    { id: "D-42", text: "|_. Item |_. Value |\n| Name | Redmine |\n", format: "textile", reason: :score },
    { id: "D-43", text: "Intro text.\n\n| not a table |\n", format: nil, reason: :no_signal },
    { id: "D-44", text: "| pipe one\n| pipe two\n", format: nil, reason: :no_signal },
    # The link scores 4 for Markdown and the bare table 4 for Textile, so the two
    # cancel. It is acceptable because the outcome switches to neither format.
    { id: "D-45", text: "[guide](https://ex.com/)\n\n| Name | Value |\n| a | 1 |\n", format: nil,
      reason: :below_threshold },
    # A separator row on its own is still Markdown evidence, independent of how
    # many rows a Textile table needs.
    { id: "D-46", text: "|---|\n", format: "common_mark", reason: :score },
    # Strong evidence on both sides (5:5) leaves the verdict open, which is right.
    { id: "D-47", text: "|_. Item |_. Value |\n|---|---|\n", format: nil, reason: :below_threshold },
    # Indented code blocks: a block that opens after a blank line is code, so what
    # it quotes says nothing about the format.
    { id: "D-48", text: INDENTED_TEXTILE_LINK, format: nil, reason: :no_signal },
    # Recorded, not a regression check: patterns anchored to the first column never
    # matched an indented line, so this scored nothing before the masking either.
    { id: "D-49", text: "Intro paragraph.\n\n    h1. Title\n\nEnd paragraph.\n", format: nil,
      reason: :no_signal },
    # A list item keeps an indented continuation, so it is not code.
    { id: "D-50", text: "- item\n    [the guide](https://ex.com/)\n", format: "common_mark", reason: :score },
    # No blank line before the indent: it continues the paragraph.
    { id: "D-51", text: "Intro paragraph.\n    \"link\":https://ex.com/\n", format: "textile", reason: :score },
    # Known limit: an indent at the very start has no blank line above it to open a
    # block, so it is scored like any other line.
    { id: "D-52", text: "    \"link\":https://ex.com/\n", format: "textile", reason: :score },
    { id: "D-53", text: "- outer\n    - inner with [the guide](https://ex.com/)\n", format: "common_mark",
      reason: :score },
    { id: "D-54", text: "Intro paragraph.\n\n\t\"link\":https://ex.com/\n\nEnd paragraph.\n", format: nil,
      reason: :no_signal },
    # A blank line inside the block does not end it.
    { id: "D-55", text: INDENTED_BLOCK_WITH_BLANK_LINE, format: nil, reason: :no_signal },
    # A line that is not indented ends the block and is scored as usual.
    { id: "D-56", text: "Intro.\n\n    code line\n\n\"link\":https://ex.com/\n", format: "textile",
      reason: :score },
    # The indent follows a one-line <pre>, not a blank line. Tracking the previous
    # line from the masked text would see a blank there and open a block by mistake.
    { id: "D-57", text: "Intro.\n\n<pre>x</pre>\n    \"link\":https://ex.com/\n", format: "textile",
      reason: :score },
    # A blank line between a list item and its indented continuation: the indent
    # still belongs to the item, so it is not code and its content is scored.
    { id: "D-58", text: "- item\n\n    [the guide](https://ex.com/)\n", format: "common_mark",
      reason: :score },
    # A second indented continuation paragraph, after another blank line, still
    # belongs to the list item: it is not code, so the Textile link it holds is
    # scored.
    { id: "D-62", text: LIST_WITH_TWO_INDENTED_CONTINUATIONS, format: "textile",
      reason: :score },
    # A Markdown heading is not a list item, so an indented block under it is code:
    # the Textile links it quotes must not decide the format.
    { id: "D-59", text: "## Usage\n\n    \"one\":https://ex.com/\n    \"two\":https://ex.org/\n",
      format: "common_mark", reason: :score },
    # A Textile table may put a dash in a cell. The row is not a separator row unless
    # it holds nothing but pipes, dashes, colons and spaces.
    { id: "D-60", text: "| - | x |\n| a | b |\n", format: "textile", reason: :score },
    { id: "D-61", text: "|:-:| x |\n| a | b |\n", format: "textile", reason: :score }
  ].freeze

  # The threshold the cases above are written against; it is also the shipped default.
  DEFAULT_THRESHOLD = 2

  context "RedmineRenderSwitcher::Detector.detect" do
    CASES.each do |row|
      should "return #{row[:format].inspect} / #{row[:reason].inspect} for #{row[:id]}" do
        result = RedmineRenderSwitcher::Detector.detect(row[:text], threshold: DEFAULT_THRESHOLD)

        evidence = "#{row[:id]}: textile=#{result.textile_score} markdown=#{result.markdown_score}"
        if row[:format].nil?
          assert_nil result.format, evidence
        else
          assert_equal row[:format], result.format, evidence
        end
        assert_equal row[:reason], result.reason, evidence
      end
    end

    should "score both formats with non-negative integers" do
      CASES.each do |row|
        result = RedmineRenderSwitcher::Detector.detect(row[:text], threshold: DEFAULT_THRESHOLD)

        assert_operator result.textile_score, :>=, 0, row[:id]
        assert_operator result.markdown_score, :>=, 0, row[:id]
      end
    end

    # CASES only records the verdict, so the block-per-rule scoring is pinned here.
    should "score a list once per block, however many lines it has" do
      result = RedmineRenderSwitcher::Detector.detect(LOOSE_DASH_LIST, threshold: DEFAULT_THRESHOLD)

      assert_equal [ 0, 3 ], [ result.textile_score, result.markdown_score ]
    end

    should "score two lists that prose separates once each" do
      result = RedmineRenderSwitcher::Detector.detect(TWO_SEPARATE_LISTS, threshold: DEFAULT_THRESHOLD)

      assert_equal [ 0, 6 ], [ result.textile_score, result.markdown_score ]
    end

    # FR-011 / FR-020: hand-written dashes must not out-score a Textile heading, so
    # the list is worth the same whether it runs to two lines or to five.
    should "keep a Textile document Textile however long its dash list runs" do
      [ 2, 5 ].each do |lines|
        text = "h1. Notes\n\n#{Array.new(lines) { |i| "- item #{i}\n" }.join}"
        result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)

        assert_equal [ 5, 3 ], [ result.textile_score, result.markdown_score ], "#{lines} lines"
        assert_equal "textile", result.format, "#{lines} lines"
      end
    end

    # Each table block is scored on its own, and a blank line ends a table.
    should "score each of two tables on its own side" do
      result = RedmineRenderSwitcher::Detector.detect(MIXED_TABLES, threshold: DEFAULT_THRESHOLD)

      assert_equal [ 4, 5 ], [ result.textile_score, result.markdown_score ]
    end

    # The context rules read the masked lines, so what a code block quotes scores
    # nothing. A fence scores 5 on each of its two lines and nothing else; a <pre>
    # block scores nothing at all.
    should "not score a list, table or Setext heading inside a code block" do
      {
        "list in a fence" => [ "Intro.\n\n```\n- a\n- b\n```\n", [ 0, 10 ] ],
        "Markdown table in a fence" => [ "Intro.\n\n```\n| a | b |\n|---|---|\n```\n", [ 0, 10 ] ],
        "Textile table in a fence" => [ "Intro.\n\n```\n| a | b |\n| c | d |\n```\n", [ 0, 10 ] ],
        "Setext heading in a fence" => [ "Intro.\n\n```\nTitle\n=====\n```\n", [ 0, 10 ] ],
        "list in a pre" => [ "Intro.\n\n<pre>\n- a\n- b\n</pre>\n", [ 0, 0 ] ],
        "table in a pre" => [ "Intro.\n\n<pre>\n| a | b |\n| c | d |\n</pre>\n", [ 0, 0 ] ]
      }.each do |name, (text, expected)|
        result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)

        assert_equal expected, [ result.textile_score, result.markdown_score ], name
      end
    end

    # A line of = under a # line is not a Setext underline: the # line is a heading
    # or a list item already, and neither takes a continuation line.
    should "not read a line of = under a # line as a Setext heading" do
      result = RedmineRenderSwitcher::Detector.detect("# Title\n=====\n", threshold: DEFAULT_THRESHOLD)

      assert_equal [ 0, 4 ], [ result.textile_score, result.markdown_score ]
    end

    # ADR-0005: the Setext rule scores each heading, not each block. One underline
    # leaves a Textile document undecided (D-38), and a second one tips it to Markdown.
    # If real documents show that to be a problem, the remedy is a new
    # Detector::VERSION, and this test is where the change becomes visible.
    should "read a Textile document with two Setext underlines as Markdown" do
      text = "h1. Title\n\nFirst\n=====\n\nSecond\n=====\n"
      result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)

      assert_equal [ 5, 8 ], [ result.textile_score, result.markdown_score ]
      assert_equal "common_mark", result.format
    end

    # A tie carries no evidence for either side, so there is nothing to report
    # however low the bar is set. With the bar at 0 the comparison used to let a
    # tie through and hand the win to whichever side the code tested second.
    should "never name a winner when the two scores are level" do
      [ 0, 1, 2, 5 ].each do |threshold|
        result = RedmineRenderSwitcher::Detector.detect(EXACT_TIE, threshold: threshold)

        assert_equal result.textile_score, result.markdown_score, "the fixture must stay a tie"
        assert_nil result.format, "threshold #{threshold} named a winner on a tie"
        assert_equal :below_threshold, result.reason
      end
    end

    # A margin of one is still a margin, so the lowest usable bar must let it pass.
    should "name a winner on a margin of one when the threshold is at its lowest" do
      result = RedmineRenderSwitcher::Detector.detect(NARROW_MARGIN, threshold: 0)

      assert_equal 1, (result.textile_score - result.markdown_score).abs
      assert_equal "textile", result.format
    end

    # The image pattern and the link pattern both match "![alt](url)", so an image
    # used to be worth two notations instead of one.
    should "score a Markdown image once, not as an image and a link as well" do
      image = RedmineRenderSwitcher::Detector.detect("![logo](https://ex.com/a.png)\n",
                                                    threshold: DEFAULT_THRESHOLD)
      link = RedmineRenderSwitcher::Detector.detect("[logo](https://ex.com/a.png)\n",
                                                   threshold: DEFAULT_THRESHOLD)

      assert_equal link.markdown_score, image.markdown_score
      assert_equal 0, image.textile_score
    end

    should "honour a threshold that no score difference can reach" do
      result = RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: 1_000)

      assert_nil result.format
      assert_equal :below_threshold, result.reason
    end

    # T014 / FR-007: detection never touches the text it was handed.
    should "not modify the text it is given" do
      CASES.each do |row|
        text = +row[:text].dup
        before = text.dup

        RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)

        assert_equal before, text, row[:id]
      end
    end

    should "never return nil" do
      CASES.each do |row|
        assert_not_nil RedmineRenderSwitcher::Detector.detect(row[:text], threshold: DEFAULT_THRESHOLD),
                       row[:id]
      end
    end
  end

  # D-17..D-19 say what the scores come out as; this says why that is the right
  # answer, by asking RedCloth what it would actually render.
  context "RedmineRenderSwitcher::Detector::TEXTILE_INLINE_CODE" do
    should "match exactly where RedCloth renders inline code" do
      INLINE_CODE_GROUND_TRUTH.each do |line|
        assert_equal textile_html(line).include?("<code>"),
                     RedmineRenderSwitcher::Detector::TEXTILE_INLINE_CODE.match?(line),
                     line
      end
    end
  end

  # ADR-0006: +text+ is Textile's insertion notation. The non-ASCII fixtures below
  # (CJK prose and punctuation) are deliberate: the boundary rules have to cope with
  # exactly that text. Each list is checked against what RedCloth really renders, so
  # the pattern can only count what Textile turns into an insertion, apart from the
  # misses and residual false positives the ADR lists.
  INSERTION_COUNTED = [
    "+下線+", "これは +下線+ です", "(+ins+)", "+*bold*+", "*+ins+*",
    "+ins+.", "+ins+,", "+ins+;", "+ins+:", "+ins+!", "+ins+?", "+ins+。", "+ins+、",
    "+ins+）", "| +ins+ | x |", "|+ins+|x|", "* +ins+ item", "# +ins+ item", "h2. +ins+",
    "+ab+ c +de+", "Ctrl +Alt+ Del", "x\t+ins+\ty", "x *+ins+* y", "a\n|+ins+|\n"
  ].freeze

  INSERTION_NOT_NOTATION = [
    "これは+下線+です", "これは+下線+ です",
    "これは +下線+です", "（+ins+）", "「+ins+」", "[+ins+]",
    "\"+ins+\"", "=+ins+", ":+ins+", "/+ins+/", "--format=+%h+", "https://ex.com/?q=+a+", "`+ins+`",
    "<code>+ins+</code>", "[+ins+](https://ex.com/)", "C++/C++", "C++ and C++", "i++ + ++j", "a+b+c",
    "Ctrl+Alt+Del", "+1 and +2", "+1, +2, +3", "+ item +", "+ item", "+++ b/file.rb",
    "　+下線+　", "x +ab+\u3000y", "x\u3000+ab+ y", "x*+ab+*y", "x|+ab+|y", "x |+ab+| y"
  ].freeze

  INSERTION_MISSED = [
    "+a+", "+1+", "+字+", "x = +a+ b", "_+ins+_", "++x++", "+++x+++", "+ins+/x", "+ins+-x",
    "+ins+'s", "+foo\nbar+", "+ab+cd+", "+ab + cd+", "+C++ and Java", "++ab+ x", "x +ab++ y",
    "|a|+ins+|"
  ].freeze

  # Counted although Textile renders no insertion (ADR-0006, Consequences). Pinned so
  # that a change to the pattern cannot widen or close these gaps unnoticed.
  INSERTION_RESIDUAL = [
    "|+ins+", "<!-- +abc+ -->", "<code> +ins+ </code>", "<notextile> +ins+ </notextile>"
  ].freeze

  INSERTION_LABELS = "+*Label one:*+ \r\n\r\nplain text\r\n\r\n+*Label two:*+\r\n\r\n" \
                     "+*Label three:*+ \r\n\r\n+*Label four:*+\r\n"

  # Lines whose Textile image verdict is pinned against RedCloth itself, so that
  # tightening or loosening the pattern cannot drift away from what Textile
  # actually renders (ADR-0007). The four lists below hold what the pattern
  # counts and Textile renders, what neither does, the misses and the residual
  # false positives the ADR accepts.

  # Textile renders an image and the pattern counts it (C-1). Attribute blocks
  # (alignment, class, style, language) and alternative text may hold spaces.
  IMAGE_COUNTED = [
    "!{width: 794px}.clipboard-202512151503-abcde.png!",
    "!{width: 794px}image.png!",
    "!{width: 50%; height: 20px}.a.png!",
    "!{width: 794px}https://ex.com/a.png!",
    "!{width: 794px}.a.png!:https://ex.com/",
    "text !{width: 794px}.a.png! text",
    "!image.png!",
    "!{width:794px}.a.png!",
    "!>{width: 794px}.a.png!",
    "!<{width: 794px}.a.png!",
    "!={width: 794px}.a.png!",
    "!(cls){width: 794px}.a.png!",
    "!(my cls){width: 1px}.a.png!",
    "!{width: 1px}(cls)a.png!",
    "![ja]a.png!",
    "!>(cls){width: 1px}[ja]a.png(alt t)!",
    "![ja]{width: 1px}a.png!",
    "![ja-jp]{width: 1px}a.png!",
    "!{ width: 1px}a.png!",
    "!a.png(alt (x))!",
    "!a.png(a (b) c)!",
    "!a.png((x))!",
    "!/a!",
    "!a/b!",
    "!(cls)a/b!",
    "\t!a.png!",
    "!a.png(alt text)!",
    "!{width: 794px}.a.png(alt text)!",
    "!https://ex.com/a.png(the alt)!",
    "!a.png (alt)!",
    "!a.png(alt text)!:https://ex.com/",
    "x !a.png!",
    "x>!a.png!",
    "|!a.png!|"
  ].freeze

  # Textile renders no image and the pattern must not count it (C-2). The
  # non-ASCII lines are deliberate: prose glued to the notation (CJK text without
  # spaces, full-width brackets) is itself part of what is verified.
  IMAGE_NOT_NOTATION = [
    "!<>{width: 794px}.a.png!",
    "完了しました! 次も頑張ります!",
    "Wow!{a b} c.d!",
    "Hi!(see x.y) ok!",
    "Error!(code) x.rb!",
    "!{width: 794px}!",
    "!(x y)!",
    "! a.png!",
    "!a b.png!",
    "!{width: 794px}.a\nb.png!",
    "x!a.png!",
    "これは!a.png!",
    "x.!a.png!",
    "x:!a.png!",
    "(!a.png!)",
    "「!a.png!」",
    "\"!a.png!\"",
    "*!a.png!*",
    "すごい!(笑)次はa.png!",
    "Yes!(a b)c.d!",
    "!{width: 1px}. a.png!",
    "!a(b).png!",
    "!https://ex.com/a_(b).png!",
    "!a.png  (alt)!",
    "!a.png\t(alt)!",
    "!()a.png!",
    "Hello!",
    "see https://ex.com/a!b.png! x",
    "http://ex.com/!a.png!"
  ].freeze

  # Textile renders an image but the pattern does not count it (C-3, ADR-0007):
  # a file name without a dot or a slash (a deliberate precision-first choice,
  # since Textile reads +!wow!+ as an image too), another notation wrapped around
  # the image, and an attribute block or alternative text spanning two lines.
  IMAGE_MISSED = [
    "!wow!",
    "!img_1!",
    "==!a.png!==",
    "!a.png(alt\ntext)!",
    "!(a\nb)c.png!",
    "!{width:\n1px}a.png!"
  ].freeze

  # Counted although Textile renders no image (C-4, ADR-0007): repeated or
  # out-of-order attributes, and a +|+ or +>+ that is not a table cell. Pinned so
  # that a change to the pattern cannot widen or close these gaps unnoticed.
  IMAGE_RESIDUAL = [
    "!(a)(b)c.png!",
    "!{a: b}{c: d}e.png!",
    "!(c)[ja]{w: 1px}a.png!",
    "x|!a.png!",
    "a |!a.png! b",
    "<p>!a.png!</p>"
  ].freeze

  # ADR-0008: %{color:red}text% is Textile's color span notation. The fixture
  # lists below are checked against what RedCloth really renders, so the
  # pattern can only count where Textile turns the notation into a *colored*
  # span, apart from the misses and residual false positives the ADR lists.

  # Textile renders a colored span and the pattern counts it (contracts C-1).
  # The non-ASCII lines are deliberate: prose around the notation (CJK text
  # without spaces, full-width punctuation) is itself part of what is
  # verified. The last line holds the notation inside single backticks, which
  # are not code in Textile: the span after the space renders, CommonMark
  # renders code, and the shape is counted here although its verdict ties 3:3
  # (pinned at C-5-4 below).
  COLOR_SPAN_COUNTED = [
    "結果は %{color:red}NG% でした",
    "%{color:red}a b% と %{font-size:2em}c%",
    "%{color:#f00}赤% と %{background:yellow}黄%",
    "%{color: red}空白あり%",
    "%{ color:red}x% y",
    "%{Color:red}x% y",
    "%{color:red;font-weight:bold}NG% x",
    "%{font-weight:bold; color:red}x% y",
    "%{color:red}複数\n行%",
    "結果は %{color:red}NG%。",
    "(%{color:red}NG%)",
    "*%{color:red}太字赤%*",
    "|%{color:red}x%|y|",
    "%{color:red}NG%、次",
    "%{color:red}NG%！",
    "|a|%{color:red}x%|",
    ">%{color:red}NG%",
    "a>%{color:red}x% y",
    "**%{color:red}a%**",
    "a *%{color:red}x%* y",
    "%{color:red}x%\r\ny",
    "%{;color:red}x% y",
    "結果は %{color:red}NG%でした。次は 50% です",
    "`a %{color:red}NG% b`",
    "a\t%{color:red}x% y",
    "%{\tcolor:red}x% y"
  ].freeze

  # Textile renders no span at all and the pattern must not count it
  # (contracts C-2). The non-ASCII lines are deliberate, as above.
  COLOR_SPAN_NOT_NOTATION = [
    "結果は%{color:red}NG%でした",
    "結果は %{color:red}NG%でした",
    "a%{color:red}NG%b",
    "%{color:red}NG",
    "%{color:red}NG %",
    "% {color:red} x%",
    "達成率 50% と 80% の間",
    "100%{x} 完了 50%",
    "%{color:red}a\n\nb% x",
    "%{color:red}a\r\n\r\nb% x",
    "%{color:red}a\n  \nb% x",
    "a*%{color:red}x%* y",
    "%{color:red}a%a",
    "`%{color:red}NG%`",
    "%[ja]{color:red}x% y"
  ].freeze

  # A real Textile link whose text holds the notation: Textile renders the link
  # and no span, and the link notation itself is worth 4 points.
  COLOR_SPAN_IN_LINK = "\"%{color:red}x%\":http://e.com"

  # Textile renders a span for each of these, but not a colored one: a block
  # without a color property (FR-001 (a)), a name that merely contains "color"
  # (FR-001 (b)), space between the name and the colon (FR-001 (c)), a block
  # without any colon (FR-001 (d), the shape of Ruby i18n format strings), a
  # block spanning two lines, an empty span body, and blocks whose braces or
  # quotes make Textile keep the text as the span body instead of a style. This
  # is the one place where Textile renders a span that is deliberately not
  # counted, so it is pinned against both facts: a span in the HTML, no color
  # style in it, and no Textile points. The non-ASCII lines are deliberate, as
  # above.
  COLOR_SPAN_NOT_COLORED = [
    "%{background:yellow}黄% x",
    "%{font-size:2em}c% x",
    "%{background-color:yellow}x% y",
    "%{border-color:red}x% y",
    "%{color :red}x% y",
    "%{ color : red}x% y",
    "件数は %{count}件% です",
    "エラー: %{value} は %{count} 以下%",
    "%{color:\nred}x%",
    "%{color:red}%",
    "%{{a;color:red}x% y",
    "%{color:\"red\"}x% y",
    "%{a:\"b\";color:red}x% y",
    "%{\ncolor:red}x% y"
  ].freeze

  # Textile renders a colored span but the pattern does not count it
  # (contracts C-3, ADR-0008): a body ending at a newline, a class attribute
  # before the style block, a span wrapped in emphasis other than stars, and
  # a span wrapped in three stars (the pattern allows up to two).
  COLOR_SPAN_MISSED = [
    "%{color:red}a\n%",
    "%(cls){color:red}x% y",
    "_%{color:red}x%_",
    "-%{color:red}x%-",
    "***%{color:red}x%*** y"
  ].freeze

  # Counted although Textile renders no colored span (contracts C-4,
  # ADR-0008): a pipe that is not a table cell, and values Redmine's STYLES_RE
  # rejects, which leave a bare span behind. Pinned so that a change to the
  # pattern cannot widen or close these gaps unnoticed.
  COLOR_SPAN_RESIDUAL = [
    "a|%{color:red}x% y",
    "%{color:rgb(1,2,3)}x% y",
    "%{color:}x% y"
  ].freeze

  # What a colored span looks like in RedCloth's output: a +color+ property at
  # the start of the style attribute or after another declaration. A bare
  # +color:+ substring is not enough, since +background-color:+ contains it.
  COLORED_SPAN_HTML = /<span style="(?:[^"]*;)?color:/i

  # Renders +text+ with the bare Textile formatter, skipping the plugin.
  def textile_html(text)
    klass = Redmine::WikiFormatting::Textile::Formatter
    klass.instance_method(:to_html).super_method.bind_call(klass.new(text))
  end

  # Renders +text+ with the bare CommonMark formatter, skipping the plugin.
  def common_mark_html(text)
    klass = Redmine::WikiFormatting::CommonMark::Formatter
    klass.instance_method(:to_html).super_method.bind_call(klass.new(text))
  end

  # Asserts a pattern against RedCloth's own output for four lists of inputs:
  # +counted+ (renders +tag+, pattern matches), +not_notation+ (neither),
  # +missed+ (renders, pattern does not match) and +residual+ (pattern matches,
  # does not render).
  #
  # +tag+ is a String or a Regexp. A string keeps only what +include?+ could
  # say; a regexp says what a substring cannot, such as "a span holding a
  # +color+ property" — <tt>style="background-color:yellow;"</tt> contains
  # +color:+ but is a different property, and a property that comes later in
  # the attribute list is behind other declarations.
  def assert_matches_redcloth(pattern, tag, counted:, not_notation:, missed:, residual:)
    { counted => [ true, true ], not_notation => [ false, false ],
      missed => [ true, false ], residual => [ false, true ] }.each do |texts, (renders, matches)|
      texts.each do |text|
        assert_equal renders, textile_html(text).match?(tag), text
        assert_equal matches, pattern.match?(text), text
      end
    end
  end

  # Returns the [Textile, Markdown] scores the detector gives +text+.
  def scores(text)
    result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)
    [ result.textile_score, result.markdown_score ]
  end

  # Returns [Textile score, Markdown score, format, reason] for +text+.
  def verdict(text)
    result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)
    [ result.textile_score, result.markdown_score, result.format, result.reason ]
  end

  context "RedmineRenderSwitcher::Detector::TEXTILE_INSERTION" do
    should "match exactly where RedCloth renders an insertion, apart from the accepted misses" do
      assert_matches_redcloth(RedmineRenderSwitcher::Detector::TEXTILE_INSERTION, "<ins>",
                              counted: INSERTION_COUNTED, not_notation: INSERTION_NOT_NOTATION,
                              missed: INSERTION_MISSED, residual: INSERTION_RESIDUAL)
    end

    should "leave every counted form as plain text in CommonMark" do
      (INSERTION_COUNTED + INSERTION_RESIDUAL).each do |text|
        assert_not_includes common_mark_html(text), "<ins>", text
      end
    end

    should "add Textile points for every counted form (C-1)" do
      INSERTION_COUNTED.each do |text|
        assert_operator scores(text).first, :>=, 3, text
      end
    end

    should "add no Textile points for text Textile leaves alone (C-2)" do
      INSERTION_NOT_NOTATION.each do |text|
        assert_equal 0, scores(text).first, text
      end
    end

    should "detect a document of underlined labels as Textile 12:0 (C-1-1)" do
      result = RedmineRenderSwitcher::Detector.detect(INSERTION_LABELS, threshold: DEFAULT_THRESHOLD)

      assert_equal [ 12, 0 ], [ result.textile_score, result.markdown_score ]
      assert_equal "textile", result.format
      assert_equal :score, result.reason
    end

    should "decide a lone occurrence, or leave a single-character form to the site setting (C-1-2, C-1-4, C-3)" do
      {
        "これは +下線+ です。\n" => [ 3, 0, "textile", :score ],
        "Ctrl +Alt+ Del\n" => [ 3, 0, "textile", :score ],
        "+a+\n" => [ 0, 0, nil, :no_signal ],
        "x = +a+ b\n" => [ 0, 0, nil, :no_signal ]
      }.each do |text, expected|
        result = RedmineRenderSwitcher::Detector.detect(text, threshold: DEFAULT_THRESHOLD)

        assert_equal expected,
                     [ result.textile_score, result.markdown_score, result.format, result.reason ], text
      end
    end

    should "count each occurrence (C-1-3)" do
      assert_equal [ 6, 0 ], scores("+ab+ c +de+\n")
    end

    should "weigh against other evidence the way the contract says (C-4-1..C-4-4)" do
      dash_list = "- one\n- two\n"
      link = "[l](https://ex.com/)\n"

      assert_equal [ 3, 3 ], scores("+ab+\n\n#{dash_list}")
      assert_equal [ 3, 4 ], scores("+ab+\n\n#{link}")
      assert_equal [ 6, 3 ], scores("+ab+ +cd+\n\n#{dash_list}")
      assert_equal [ 6, 4 ], scores("+ab+ +cd+\n\n#{link}")

      one = RedmineRenderSwitcher::Detector.detect("+ab+\n\n#{dash_list}", threshold: DEFAULT_THRESHOLD)
      two = RedmineRenderSwitcher::Detector.detect("+ab+ +cd+\n\n#{link}", threshold: DEFAULT_THRESHOLD)

      assert_nil one.format
      assert_equal :below_threshold, one.reason
      assert_equal "textile", two.format
      assert_equal :score, two.reason
    end

    should "stay Markdown for inline code and ignore code blocks (C-4-5..C-4-9)" do
      inline = RedmineRenderSwitcher::Detector.detect("`+ins+`\n", threshold: DEFAULT_THRESHOLD)
      fence = RedmineRenderSwitcher::Detector.detect("Intro.\n\n```\n+ins+\n```\n", threshold: DEFAULT_THRESHOLD)

      assert_equal [ "common_mark", 0, 3 ], [ inline.format, inline.textile_score, inline.markdown_score ]
      assert_equal [ "common_mark", 0, 10 ], [ fence.format, fence.textile_score, fence.markdown_score ]
      assert_equal [ 0, 0 ], scores("Intro.\n\n<pre>\n+ins+\n</pre>\n")
      assert_equal [ 0, 0 ], scores("Intro.\n\n    +ins+\n\nEnd.\n")
      # Accepted (research decision 6): one spaced occurrence inside inline code ties.
      assert_equal [ 3, 3 ], scores("`a +bc+ d`\n")
    end
  end

  # ADR-0007: !…! is Textile's image notation. Each fixture list is checked
  # against what RedCloth really renders, so the pattern can only count what
  # Textile turns into an image, apart from the misses and residual false
  # positives the ADR lists.
  context "RedmineRenderSwitcher::Detector::TEXTILE_IMAGE" do
    should "match exactly where RedCloth renders an image, apart from the accepted misses and residuals" do
      assert_matches_redcloth(RedmineRenderSwitcher::Detector::TEXTILE_IMAGE, "<img",
                              counted: IMAGE_COUNTED, not_notation: IMAGE_NOT_NOTATION,
                              missed: IMAGE_MISSED, residual: IMAGE_RESIDUAL)
    end

    should "leave every counted form as plain text in CommonMark" do
      (IMAGE_COUNTED + IMAGE_RESIDUAL).each do |text|
        assert_not_includes common_mark_html(text), "<img", text
      end
    end

    should "add Textile points for every counted form (C-1)" do
      IMAGE_COUNTED.each do |text|
        assert_operator scores(text).first, :>=, 3, text
      end
    end

    should "decide a lone pasted image, with LF or CRLF, as Textile 3:0 (C-1-1, C-1-2)" do
      assert_equal [ 3, 0, "textile", :score ],
                   verdict("!{width: 794px}.clipboard-202512151503-abcde.png!\n")
      assert_equal [ 3, 0, "textile", :score ],
                   verdict("Some description.\r\n\r\n!{width: 794px}.clipboard-202512151503-abcde.png!\r\n")
    end

    should "count each styled image on one line (C-1-3)" do
      assert_equal [ 6, 0 ], scores("!{width: 794px}.a.png! and !{width: 10px}.b.png!\n")
    end

    should "add no Textile points for text Textile leaves alone (C-2)" do
      IMAGE_NOT_NOTATION.each do |text|
        assert_equal 0, scores(text).first, text
      end
    end

    should "leave notation glued to a word and CJK prose undecided (C-2-1, C-2-2)" do
      assert_equal [ 0, 0, nil, :no_signal ], verdict("x!a.png!")
      assert_equal [ 0, 0, nil, :no_signal ], verdict("すごい!(笑)次はa.png!")
    end

    should "weigh against other evidence and code the way the contract says (C-5)" do
      paste = "!{width: 794px}.a.png!"
      dash_list = "- one\n- two\n"
      {
        "#{paste}\n\n#{dash_list}" => [ 3, 3, nil, :below_threshold ],
        "#{paste}\n\n[l](https://ex.com/)\n" => [ 3, 4, nil, :below_threshold ],
        "#{paste} and #{paste}\n\n#{dash_list}" => [ 6, 3, "textile", :score ],
        "Intro.\n\n```\n#{paste}\n```\n" => [ 0, 10, "common_mark", :score ],
        "Intro.\n\n<pre>\n#{paste}\n</pre>\n" => [ 0, 0, nil, :no_signal ],
        "Intro.\n\n    #{paste}\n\nEnd.\n" => [ 0, 0, nil, :no_signal ],
        "`#{paste}`\n" => [ 0, 3, "common_mark", :score ]
      }.each do |text, expected|
        assert_equal expected, verdict(text), text
      end
    end

    should "leave a Markdown image followed by an exclamation mark at 3:4, below the threshold" do
      assert_equal [ 3, 4, nil, :below_threshold ], verdict("![a.png](a.png)!\n")
    end
  end

  context "RedmineRenderSwitcher::Detector::TEXTILE_COLOR_SPAN" do
    should "match exactly where RedCloth renders a colored span, apart from the accepted misses and residuals" do
      assert_matches_redcloth(RedmineRenderSwitcher::Detector::TEXTILE_COLOR_SPAN,
                              COLORED_SPAN_HTML,
                              counted: COLOR_SPAN_COUNTED, not_notation: COLOR_SPAN_NOT_NOTATION,
                              missed: COLOR_SPAN_MISSED, residual: COLOR_SPAN_RESIDUAL)
    end

    # The one deliberate disagreement with Textile's rendering: these make a
    # span in Textile but hold no color property, so they count nothing. The
    # colored-span ground truth above cannot see the span, so this pins both
    # facts separately (FR-001, FR-009).
    should "not count a styled span that has no color property (FR-001)" do
      COLOR_SPAN_NOT_COLORED.each do |text|
        assert_includes textile_html(text), "<span", text
        assert_not textile_html(text).match?(COLORED_SPAN_HTML), text
        assert_equal 0, scores(text).first, text
      end
    end

    should "leave every counted form as plain text in CommonMark" do
      (COLOR_SPAN_COUNTED + COLOR_SPAN_RESIDUAL).each do |text|
        assert_not_includes common_mark_html(text), "<span", text
      end
    end

    should "add Textile points for every counted form (C-1)" do
      COLOR_SPAN_COUNTED.each do |text|
        assert_operator scores(text).first, :>=, 3, text
      end
    end

    should "add no Textile points for text Textile leaves alone (C-2)" do
      COLOR_SPAN_NOT_NOTATION.each do |text|
        assert_equal 0, scores(text).first, text
      end
      assert_equal 4, scores(COLOR_SPAN_IN_LINK).first, COLOR_SPAN_IN_LINK
      assert_not textile_html(COLOR_SPAN_IN_LINK).match?(COLORED_SPAN_HTML)
      assert_not RedmineRenderSwitcher::Detector::TEXTILE_COLOR_SPAN.match?(COLOR_SPAN_IN_LINK)
    end

    should "decide a lone color span as Textile 3:0, LF or CRLF (C-1-1, C-1-5)" do
      assert_equal [ 3, 0, "textile", :score ], verdict("結果は %{color:red}NG% でした\n")
      assert_equal [ 3, 0, "textile", :score ],
                   verdict("Some description.\r\n\r\n結果は %{color:red}NG% でした\r\n")
    end

    should "count each occurrence on one line (C-1-2)" do
      assert_equal [ 6, 0 ], scores("%{color:red}NG% と %{color:blue}OK% x\n")
    end

    should "accept spaces inside the attribute block (C-1-3, C-1-4)" do
      assert_equal [ 3, 0, "textile", :score ], verdict("%{color: red}空白あり%\n")
      assert_equal [ 3, 0, "textile", :score ], verdict("%{font-weight:bold; color:red}x% y\n")
    end

    should "add to a Textile heading's evidence (C-1-6)" do
      assert_equal [ 8, 0, "textile", :score ], verdict("h2. Title\n\n%{color:red}NG% x\n")
    end

    should "stay no_signal for prose and look-alikes (C-2-1..C-2-5)" do
      {
        "達成率 50% と 80% の間\n" => [ 0, 0, nil, :no_signal ],
        "結果は%{color:red}NG%でした\n" => [ 0, 0, nil, :no_signal ],
        "%{background:yellow}黄% x\n" => [ 0, 0, nil, :no_signal ],
        "%{background-color:yellow}x% y\n" => [ 0, 0, nil, :no_signal ],
        "件数は %{count}件% です\n" => [ 0, 0, nil, :no_signal ]
      }.each do |text, expected|
        assert_equal expected, verdict(text), text
      end
    end

    should "weigh against other evidence and code the way the contract says (C-5-1..C-5-5)" do
      span = "%{color:red}NG%"
      {
        "Intro.\n\n```\n#{span}\n```\n" => [ 0, 10, "common_mark", :score ],
        "Intro.\n\n<pre>\n#{span}\n</pre>\n" => [ 0, 0, nil, :no_signal ],
        "Intro.\n\n    #{span}\n\nEnd.\n" => [ 0, 0, nil, :no_signal ],
        "`a #{span} b`\n" => [ 3, 3, nil, :below_threshold ],
        "# Title\n\n[link](http://e.com) #{span} x\n" => [ 3, 8, "common_mark", :score ]
      }.each do |text, expected|
        assert_equal expected, verdict(text), text
      end
    end
  end

  context "RedmineRenderSwitcher::Detector::Result" do
    should "carry only the format, the two scores and the reason" do
      assert_equal %i[format textile_score markdown_score reason],
                   RedmineRenderSwitcher::Detector::Result.members
    end

    should "not retain the input text" do
      result = RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_not(result.to_h.values.any? { |v| v.is_a?(String) && v.include?("Release procedure") })
    end

    # The directive answers before any scoring happens, so a directive result has
    # no evidence to carry. Building it through the factory keeps that invariant in
    # one place instead of restating the two zeroes at the call site.
    should "build a directive result with no scores behind it" do
      result = RedmineRenderSwitcher::Detector::Result.directive("textile")

      assert_equal "textile", result.format
      assert_equal :directive, result.reason
      assert_equal 0, result.textile_score
      assert_equal 0, result.markdown_score
    end

    should "be frozen once built" do
      result = RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_raises(NoMethodError) { result.format = "common_mark" }
    end

    # Ruby 3.1 has no Data, so a keyword Struct stands in for it. A Struct is
    # writable through its index operator as well as through its setters.
    should "reject modification through the index writer too" do
      result = RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_raises(NoMethodError, FrozenError) { result[:format] = "common_mark" }
    end

    should "be built from keywords only" do
      assert_raises(ArgumentError) { RedmineRenderSwitcher::Detector::Result.new("textile", 0, 0, :directive) }
    end
  end

  # FR-021: every detection is explainable from the debug log, and only from it.
  context "detection logging" do
    setup do
      @io = StringIO.new
      @original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(@io)
      @original_settings = Setting.plugin_redmine_render_switcher
      Setting.plugin_redmine_render_switcher =
        { "auto_detect_enabled" => "1", "score_threshold" => "2" }
    end

    teardown do
      Rails.logger = @original_logger
      Setting.plugin_redmine_render_switcher = @original_settings
    end

    should "report the verdict, both scores and the reason at debug level" do
      Rails.logger.level = ::Logger::DEBUG

      RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      log = @io.string

      assert_includes log, RedmineRenderSwitcher::Logger::PREFIX
      assert_match(/format=textile/, log)
      assert_match(/textile_score=\d+/, log)
      assert_match(/markdown_score=\d+/, log)
      assert_match(/reason=score/, log)
    end

    should "never write the text itself to the log" do
      Rails.logger.level = ::Logger::DEBUG

      RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_not_includes @io.string, "Release procedure"
    end

    should "write nothing at all at info level" do
      Rails.logger.level = ::Logger::INFO

      RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_equal "", @io.string
    end

    should "report a directive verdict too, without running the detector" do
      Rails.logger.level = ::Logger::DEBUG
      Setting.text_formatting = "textile"

      Redmine::WikiFormatting.to_html(
        "textile", "<!-- render_switcher: markdown -->\n\n# Start the server\n# Configure it\n"
      )

      log = @io.string

      assert_match(/format=common_mark/, log)
      assert_match(/reason=directive/, log)
    end
  end

  context "RedmineRenderSwitcher::Detector::VERSION" do
    should "be an Integer" do
      assert_kind_of Integer, RedmineRenderSwitcher::Detector::VERSION
    end

    # ADR-0006 (Textile insertion notation), ADR-0007 (Textile image notation
    # with styled attribute blocks) and ADR-0008 (Textile color span notation)
    # move verdicts too, so HTML cached before them must not be reused. This
    # value must never be lowered.
    should "be at least 8 so that HTML cached before the color span rule is not reused" do
      assert_operator RedmineRenderSwitcher::Detector::VERSION, :>=, 8
    end
  end
end
