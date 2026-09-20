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
      klass = Redmine::WikiFormatting::Textile::Formatter

      INLINE_CODE_GROUND_TRUTH.each do |line|
        rendered = klass.instance_method(:to_html).super_method.bind_call(klass.new(line))

        assert_equal rendered.include?("<code>"),
                     RedmineRenderSwitcher::Detector::TEXTILE_INLINE_CODE.match?(line),
                     line
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

    # The ADR-0005 rule changes and the list-continuation masking fix both move
    # verdicts, so HTML cached before them must not be reused. This value must
    # never be lowered.
    should "be at least 5 so that HTML cached before the ADR-0005 rule changes and the list-continuation fix is not reused" do
      assert_operator RedmineRenderSwitcher::Detector::VERSION, :>=, 5
    end
  end
end
