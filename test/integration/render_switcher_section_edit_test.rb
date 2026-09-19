# frozen_string_literal: true

require File.expand_path("../test_helper", __dir__)

# R-03 / US2 scenario 3: section-edit links are numbered by counting the <hN>
# elements of the rendered HTML (ApplicationHelper#parse_sections), while
# get_section / update_section number them from the source with the formatter's
# extract_sections. When the plugin delegates, both have to agree, and a section
# save must not disturb a single byte outside the edited section.
class RenderSwitcherSectionEditTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :enabled_modules, :wikis, :wiki_pages, :wiki_contents, :wiki_content_versions,
           :trackers, :issue_statuses, :enumerations, :issues

  PAGE_TITLE = "RenderSwitcherSections"

  MARKDOWN_BODY = <<~'TEXT'
    ## A

    text a

    ## B

    text b

    ## C

    text c
  TEXT

  def setup
    super
    @original_format = Setting.text_formatting
    @original_settings = Setting.plugin_redmine_render_switcher
    # The site says Textile; the page is written in Markdown.
    Setting.text_formatting = "textile"
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => "1", "score_threshold" => "2" }
    log_user("admin", "admin")
    put("/projects/ecookbook/wiki/#{PAGE_TITLE}",
        params: { content: { text: MARKDOWN_BODY, comments: "created by test" } })
    @page = WikiPage.find_by(title: PAGE_TITLE)
  end

  def teardown
    @page&.destroy
    Setting.text_formatting = @original_format
    Setting.plugin_redmine_render_switcher = @original_settings
    super
  end

  test "section edit links are numbered the same way extract_sections numbers them" do
    get "/projects/ecookbook/wiki/#{PAGE_TITLE}"

    assert_response :success
    # Section 1 never gets a link; 2 and 3 do.
    assert_select "a[href=?]", "/projects/ecookbook/wiki/#{PAGE_TITLE}/edit?section=1", 0
    assert_select "a[href=?]", "/projects/ecookbook/wiki/#{PAGE_TITLE}/edit?section=2"
    assert_select "a[href=?]", "/projects/ecookbook/wiki/#{PAGE_TITLE}/edit?section=3"

    get "/projects/ecookbook/wiki/#{PAGE_TITLE}/edit?section=2"

    assert_response :success
    assert_select "textarea[name=?]", "content[text]", text: "## B\n\ntext b"
  end

  test "saving one section leaves every other byte of the page alone" do
    formatter = Redmine::WikiFormatting.formatter_for("textile")
    before = @page.content.text
    _section, hash = formatter.new(before).get_section(2)

    put("/projects/ecookbook/wiki/#{PAGE_TITLE}",
        params: {
          content: { text: "## B\n\ntext b edited", version: @page.content.version },
          section: 2,
          section_hash: hash
        })

    assert_response :redirect
    after = @page.reload.content.text

    assert_includes after, "text b edited"
    assert_equal formatter.new(before).update_section(2, "## B\n\ntext b edited"), after
    assert_includes after, "## A\n\ntext a"
    assert_includes after, "## C\n\ntext c"
  end
end

# US3 / FR-012..FR-016: the explicit directive decides the format, never shows up
# on screen, and survives a section save.
class RenderSwitcherDirectiveRenderingTest < ActiveSupport::TestCase
  TEXTILE_DIRECTIVE = "<!-- render_switcher: textile -->"
  MARKDOWN_DIRECTIVE = "<!-- render_switcher: markdown -->"

  TEXTILE_SECTIONS = "#{TEXTILE_DIRECTIVE}\n\nh2. A\n\ntext a\n\nh2. B\n\ntext b\n"
  TEXTILE_SECTIONS_NO_BLANK_LINE = "#{TEXTILE_DIRECTIVE}\nh2. A\n\ntext a\n\nh2. B\n\ntext b\n"
  TEXTILE_ORDERED_LIST = "#{MARKDOWN_DIRECTIVE}\n\n# Start the server\n# Configure it\n# Verify the result\n"

  def setup
    @original_format = Setting.text_formatting
    @original_settings = Setting.plugin_redmine_render_switcher
    # A threshold no score difference can reach, so that only the directive can
    # decide the format. Without it these cases would pass on scoring alone and
    # would not be testing the directive at all.
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => "1", "score_threshold" => "1000" }
  end

  def teardown
    Setting.text_formatting = @original_format
    Setting.plugin_redmine_render_switcher = @original_settings
  end

  # V-10
  should "never leak the directive into the rendered HTML" do
    %w[textile common_mark].each do |format|
      Setting.text_formatting = format

      [ TEXTILE_SECTIONS, TEXTILE_ORDERED_LIST ].each do |body|
        html = Redmine::WikiFormatting.to_html(format, body)

        assert_not_includes html, "render_switcher", "#{format} leaked the directive"
      end
    end
  end

  # V-11
  should "cut the first section at the first heading when a blank line follows the directive" do
    Setting.text_formatting = "common_mark"
    formatter = Redmine::WikiFormatting.formatter_for("common_mark")

    assert_equal "h2. A\n\ntext a", formatter.new(TEXTILE_SECTIONS).get_section(1).first
  end

  # V-12
  should "keep the directive line when a section is saved" do
    Setting.text_formatting = "common_mark"
    formatter = Redmine::WikiFormatting.formatter_for("common_mark")

    updated = formatter.new(TEXTILE_SECTIONS).update_section(1, "h2. A2\n\ntext a2")

    assert updated.start_with?(TEXTILE_DIRECTIVE), "the directive line was dropped"
    assert_includes updated, "h2. B\n\ntext b"
  end

  # V-13: without a blank line after the directive, Textile numbers sections one
  # off. That is Redmine's own behaviour for anything on the first line, not
  # something this plugin introduces, and correcting the text would break FR-007.
  should "reproduce plain Redmine's Textile offset when no blank line follows the directive" do
    Setting.text_formatting = "common_mark"
    formatter = Redmine::WikiFormatting.formatter_for("common_mark")

    plugin_section = formatter.new(TEXTILE_SECTIONS_NO_BLANK_LINE).get_section(1).first
    textile_class = Redmine::WikiFormatting::Textile::Formatter
    core_section = textile_class.instance_method(:get_section)
                                .super_method
                                .bind_call(textile_class.new(TEXTILE_SECTIONS_NO_BLANK_LINE), 1)
                                .first

    assert_equal "h2. B\n\ntext b", plugin_section
    assert_equal core_section, plugin_section
  end

  # V-14
  should "let a markdown directive beat the score on a Textile ordered list" do
    Setting.text_formatting = "textile"

    html = Redmine::WikiFormatting.to_html("textile", TEXTILE_ORDERED_LIST)

    assert_match(/<h1[^>]*>Start the server/, html)
    assert_not_includes html, "<ol>"
  end
end
