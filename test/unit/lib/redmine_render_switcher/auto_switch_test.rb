# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherAutoSwitchTest < ActiveSupport::TestCase
  # Instrumentation for C-11: counts how often the detector actually runs.
  # This is not a mock; the real detector still does the work.
  module DetectCounter
    def detect(text, threshold:)
      RedmineRenderSwitcherAutoSwitchTest.detect_calls += 1
      super
    end
  end

  class << self
    attr_accessor :detect_calls
  end
  self.detect_calls = 0

  RedmineRenderSwitcher::Detector.singleton_class.prepend(DetectCounter)

  TEXTILE_BODY = %(h2. みだし\n\n"link":https://ex.com/\n)
  MARKDOWN_BODY = %(## みだし\n\n[link](https://ex.com/)\n)
  PLAIN_BODY = "これは普通の日本語の文章です。記法の特徴はありません。\n"

  # Markdown sections, used while the site is set to Textile so that the section
  # helpers have to work off the delegate's separators rather than Textile's.
  MARKDOWN_SECTIONS = <<~'TEXT'
    ## A

    text a

    ## B

    text b
  TEXT

  FORMATTER_CLASSES = [
    Redmine::WikiFormatting::Textile::Formatter,
    Redmine::WikiFormatting::CommonMark::Formatter
  ].freeze

  def setup
    @original_format = Setting.text_formatting
    @original_settings = Setting.plugin_redmine_render_switcher
  end

  def teardown
    Setting.text_formatting = @original_format
    Setting.plugin_redmine_render_switcher = @original_settings
  end

  # Renders the way Redmine would with this plugin not installed: the formatter
  # class's own +to_html+, skipping the prepended module.
  def core_to_html(format, text)
    klass = Redmine::WikiFormatting.formatter_for(format)
    klass.instance_method(:to_html).super_method.bind_call(klass.new(text))
  end

  def enable_auto_detect(enabled)
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => enabled ? "1" : "0", "score_threshold" => "2" }
  end

  context "AutoSwitch delegation" do
    setup { enable_auto_detect(true) }

    # C-01
    should "render Textile content as Textile while the site is set to Markdown" do
      Setting.text_formatting = "common_mark"

      html = Redmine::WikiFormatting.to_html("common_mark", TEXTILE_BODY)

      assert_includes html, "<h2>みだし</h2>"
      assert_includes html, 'href="https://ex.com/"'
    end

    # C-02
    should "render Markdown content as Markdown while the site is set to Textile" do
      Setting.text_formatting = "textile"

      html = Redmine::WikiFormatting.to_html("textile", MARKDOWN_BODY)

      assert_includes html, "<h2>みだし</h2>"
      assert_includes html, 'href="https://ex.com/"'
    end

    # C-03
    should "not delegate when the content already matches the site format" do
      assert_equal core_to_html("textile", TEXTILE_BODY),
                   Redmine::WikiFormatting.to_html("textile", TEXTILE_BODY)
      assert_equal core_to_html("common_mark", MARKDOWN_BODY),
                   Redmine::WikiFormatting.to_html("common_mark", MARKDOWN_BODY)
    end

    # C-04
    should "keep the site format for text that carries no signal" do
      %w[textile common_mark].each do |format|
        Setting.text_formatting = format

        assert_equal core_to_html(format, PLAIN_BODY),
                     Redmine::WikiFormatting.to_html(format, PLAIN_BODY),
                     "plain text must stay on #{format}"
      end
    end

    # C-06
    should "survive rendering the same delegating text many times" do
      Setting.text_formatting = "common_mark"

      100.times do
        Redmine::WikiFormatting.to_html("common_mark", TEXTILE_BODY)
      end

      assert_includes Redmine::WikiFormatting.to_html("common_mark", TEXTILE_BODY), "<h2>みだし</h2>"
    end

    # C-07
    should "cut sections on the delegate's separators" do
      Setting.text_formatting = "textile"
      formatter = Redmine::WikiFormatting.formatter_for("textile")

      section, hash = formatter.new(MARKDOWN_SECTIONS).get_section(1)

      assert_equal "## A\n\ntext a", section
      assert_not_nil hash
      assert_equal "## B\n\ntext b", formatter.new(MARKDOWN_SECTIONS).get_section(2).first
    end

    # C-08
    should "keep everything but the edited section byte-identical across ten round trips" do
      Setting.text_formatting = "textile"
      formatter = Redmine::WikiFormatting.formatter_for("textile")

      body = MARKDOWN_SECTIONS.dup
      section, hash = formatter.new(body).get_section(1)
      body = formatter.new(body).update_section(1, section, hash)
      stable = body.dup

      10.times do |i|
        section, hash = formatter.new(body).get_section(1)
        body = formatter.new(body).update_section(1, section, hash)

        assert_equal stable, body, "the body drifted on round trip #{i + 1}"
      end

      assert_includes body, "## B\n\ntext b"
    end

    # C-09
    should "keep a leading directive line through a section save" do
      Setting.text_formatting = "textile"
      # Only the directive may decide here: no score difference can reach 1000.
      Setting.plugin_redmine_render_switcher =
        { "auto_detect_enabled" => "1", "score_threshold" => "1000" }
      directive = "<!-- render_switcher: markdown -->"
      body = "#{directive}\n\n#{MARKDOWN_SECTIONS}"
      formatter = Redmine::WikiFormatting.formatter_for("textile")

      updated = formatter.new(body).update_section(1, "## A2\n\ntext a2")

      assert updated.start_with?(directive), "the directive line was dropped"
      assert_equal "#{directive}\n\n## A2\n\ntext a2\n\n## B\n\ntext b", updated
    end

    # C-11
    should "detect once per formatter instance and reuse the same delegate" do
      Setting.text_formatting = "common_mark"
      formatter = Redmine::WikiFormatting.formatter_for("common_mark").new(TEXTILE_BODY)

      before = self.class.detect_calls
      formatter.to_html
      formatter.extract_sections(1)
      formatter.get_section(1)

      assert_equal 1, self.class.detect_calls - before
    end
  end

  context "AutoSwitch with auto-detection disabled" do
    setup { enable_auto_detect(false) }

    # C-05
    should "render all four combinations exactly as an uninstalled plugin would" do
      [ TEXTILE_BODY, MARKDOWN_BODY ].each do |body|
        %w[textile common_mark].each do |format|
          Setting.text_formatting = format

          assert_equal core_to_html(format, body),
                       Redmine::WikiFormatting.to_html(format, body),
                       "#{format} must be untouched when detection is off"
        end
      end
    end

    should "not run the detector at all" do
      Setting.text_formatting = "common_mark"

      before = self.class.detect_calls
      Redmine::WikiFormatting.to_html("common_mark", TEXTILE_BODY)

      assert_equal 0, self.class.detect_calls - before
    end
  end

  context "AutoSwitch installation" do
    # C-10
    should "stay applied exactly once however often it is installed" do
      3.times do
        FORMATTER_CLASSES.each { |klass| RedmineRenderSwitcher::AutoSwitch.prepend_to(klass) }
      end

      FORMATTER_CLASSES.each do |klass|
        count = klass.ancestors.count { |m| m.name == "RedmineRenderSwitcher::AutoSwitch" }

        assert_equal 1, count, "#{klass} must carry AutoSwitch once"
      end
    end
  end
end
