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
  MARKDOWN_WITH_MENTIONS = <<~'TEXT'
    Thanks @alice and @bob for the review.

    This is an **important** change.
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

  NARROW_MARGIN = <<~'TEXT'
    bq. quoted line

    **emphasis**
  TEXT

  # One notation from each side, weighted the same, so the two scores land level.
  EXACT_TIE = <<~'TEXT'
    Read @Setting.text_formatting@ for it.

    There is **emphasis** here too.
  TEXT

  MIXED_AND_CLOSE = <<~'TEXT'
    h2. Textile heading

    "link":https://ex.com/

    ## Markdown heading

    [link](https://ex.com/)
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
    { id: "D-21", text: NON_ASCII_MARKDOWN, format: "common_mark", reason: :score }
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
  end
end
