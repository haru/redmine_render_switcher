# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherDetectorTest < ActiveSupport::TestCase
  TEXTILE_TYPICAL = <<~'TEXT'
    h1. リリース手順

    "公式サイト":https://redmine.org/ を参照すること。

    bq. 引用文はここに書く。

    |_. 項目 |_. 値 |
    | 名前 | Redmine |

    コードは @Setting.text_formatting@ で参照する。

    !https://example.com/logo.png!
  TEXT

  MARKDOWN_TYPICAL = <<~'TEXT'
    # リリース手順

    [公式サイト](https://redmine.org/) を参照すること。

    > 引用文はここに書く。

    | 項目 | 値 |
    | --- | --- |
    | 名前 | Redmine |

    コードは `Setting.text_formatting` で参照する。

    ![logo](https://example.com/logo.png)

    ```ruby
    puts "hello"
    ```
  TEXT

  PLAIN_JAPANESE = "これは普通の日本語の文章です。記法の特徴はありません。\n"

  TEXTILE_SHORT = <<~'TEXT'
    h2. みだし

    "link":https://ex.com/
  TEXT

  MARKDOWN_SHORT = <<~'TEXT'
    ## みだし

    [link](https://ex.com/)
  TEXT

  TEXTILE_ORDERED_LIST = <<~'TEXT'
    # 起動する
    # 設定する
    # 確認する
  TEXT

  TEXTILE_NESTED_ORDERED_LIST = <<~'TEXT'
    # 準備する
    ## 資材を集める
    ## 場所を確保する
    # 実行する
  TEXT

  MARKDOWN_H1_ONLY = <<~'TEXT'
    # タイトル

    本文です。
  TEXT

  MARKDOWN_H1_AND_H2 = <<~'TEXT'
    # タイトル

    ## 節

    本文です。
  TEXT

  MARKDOWN_MANY_HEADINGS = <<~'TEXT'
    # タイトル

    ## 節 1

    本文。

    ## 節 2

    本文。

    ### 小節

    本文。
  TEXT

  URL_ONLY = "https://example.com/path/to/page\n"

  SHARED_SYNTAX_ONLY = <<~'TEXT'
    * りんご
    * みかん

    > 引用文
  TEXT

  TEXTILE_WITH_MARKDOWN_IN_PRE = <<~'TEXT'
    h2. サンプル

    <pre>
    [link](https://ex.com/)
    **bold**
    </pre>

    "参照":https://ex.com/
  TEXT

  MARKDOWN_WITH_TEXTILE_IN_FENCE = <<~'TEXT'
    ## サンプル

    ```
    h1. これは textile
    "link":https://ex.com/
    ```

    [参照](https://ex.com/)
  TEXT

  NARROW_MARGIN = <<~'TEXT'
    bq. 引用文

    **強調**
  TEXT

  MIXED_AND_CLOSE = <<~'TEXT'
    h2. Textile 見出し

    "link":https://ex.com/

    ## Markdown 見出し

    [link](https://ex.com/)
  TEXT

  # Each row is one detection case: input text, expected format, expected reason.
  # This table is the case set SC-002 refers to; every row must match, and a new
  # row is added before the fix whenever a misdetection is found.
  CASES = [
    { id: "D-01", text: TEXTILE_TYPICAL, format: "textile", reason: :score },
    { id: "D-02", text: MARKDOWN_TYPICAL, format: "common_mark", reason: :score },
    { id: "D-03", text: PLAIN_JAPANESE, format: nil, reason: :no_signal },
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
    { id: "D-16", text: MIXED_AND_CLOSE, format: nil, reason: :below_threshold }
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

  context "RedmineRenderSwitcher::Detector::Result" do
    should "carry only the format, the two scores and the reason" do
      assert_equal %i[format textile_score markdown_score reason],
                   RedmineRenderSwitcher::Detector::Result.members
    end

    should "not retain the input text" do
      result = RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_not(result.to_h.values.any? { |v| v.is_a?(String) && v.include?("リリース手順") })
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

      assert_not_includes @io.string, "リリース手順"
    end

    should "write nothing at all at info level" do
      Rails.logger.level = ::Logger::INFO

      RedmineRenderSwitcher::Detector.detect(TEXTILE_TYPICAL, threshold: DEFAULT_THRESHOLD)

      assert_equal "", @io.string
    end

    should "report a directive verdict too, without running the detector" do
      Rails.logger.level = ::Logger::DEBUG
      Setting.text_formatting = "textile"

      Redmine::WikiFormatting.to_html("textile", "<!-- render_switcher: markdown -->\n\n# 起動する\n# 設定する\n")

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
