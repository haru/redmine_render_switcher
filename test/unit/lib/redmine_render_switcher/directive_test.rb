# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherDirectiveTest < ActiveSupport::TestCase
  CASES = [
    { id: "V-01", text: "<!-- render_switcher: textile -->\n\nh2. A\n", expected: "textile" },
    { id: "V-02", text: "<!-- render_switcher: markdown -->\n\n## A\n", expected: "common_mark" },
    { id: "V-03", text: "<!--render_switcher:textile-->\n\nh2. A\n", expected: "textile" },
    { id: "V-04", text: "<!-- RENDER_SWITCHER: TEXTILE -->\n\nh2. A\n", expected: "textile" },
    { id: "V-05", text: "本文の先頭行\n<!-- render_switcher: textile -->\n", expected: nil },
    { id: "V-06", text: "<!-- render_switcher: html -->\n\nh2. A\n", expected: nil },
    { id: "V-07", text: "{{render_switcher_textile}}\n\nh2. A\n", expected: nil },
    { id: "V-08", text: "<!-- render_switcher: textile -->", expected: "textile" },
    { id: "V-09", text: "", expected: nil }
  ].freeze

  context "RedmineRenderSwitcher::Directive.parse" do
    CASES.each do |row|
      should "return #{row[:expected].inspect} for #{row[:id]}" do
        parsed = RedmineRenderSwitcher::Directive.parse(row[:text])

        if row[:expected].nil?
          assert_nil parsed, row[:id]
        else
          assert_equal row[:expected], parsed, row[:id]
        end
      end
    end

    # V-08 also asserts non-destructiveness (FR-007).
    should "not modify the text it is given" do
      CASES.each do |row|
        text = row[:text].dup
        before = text.dup

        RedmineRenderSwitcher::Directive.parse(text)

        assert_equal before, text, row[:id]
      end
    end

    should "not offer a way to strip the directive from the text" do
      # R-04: both renderers drop HTML comments, so nothing needs removing, and a
      # remover would be the thing that deletes the directive on a section save.
      assert_not RedmineRenderSwitcher::Directive.respond_to?(:strip)
      assert_not RedmineRenderSwitcher::Directive.respond_to?(:remove)
    end

    should "not be registered as a Redmine macro" do
      # catch_macros runs before rendering and would replace a registered
      # {{...}} with {{macro(0)}}, destroying the string detection reads.
      assert_not Redmine::WikiFormatting::Macros.available_macros.key?(:render_switcher)
      assert_not Redmine::WikiFormatting::Macros.available_macros.key?(:render_switcher_textile)
    end
  end
end
