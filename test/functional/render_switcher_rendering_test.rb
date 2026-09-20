# frozen_string_literal: true

require File.expand_path("../test_helper", __dir__)

# FR-008: detection must reach every place Redmine renders formatted text, which is
# every place that goes through ApplicationHelper#textilizable.
class RenderSwitcherRenderingTest < Redmine::HelperTest
  include ApplicationHelper

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :enumerations, :journals,
           :wikis, :wiki_pages, :wiki_contents,
           :news, :documents, :boards, :messages,
           :custom_fields, :custom_values, :enabled_modules

  TEXTILE_BODY = %(h2. Heading\n\n"link":https://ex.com/\n)

  def setup
    super
    @original_format = Setting.text_formatting
    @original_settings = Setting.plugin_redmine_render_switcher
    Setting.text_formatting = "common_mark"
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => "1", "score_threshold" => "2" }
  end

  def teardown
    Setting.text_formatting = @original_format
    Setting.plugin_redmine_render_switcher = @original_settings
    super
  end

  # Every formatted-text holder Redmine renders, paired with its text attribute.
  def formatted_text_holders
    issue = Issue.find(1)
    issue.description = TEXTILE_BODY

    journal = issue.journals.first
    journal.notes = TEXTILE_BODY

    wiki_content = WikiPage.first.content
    wiki_content.text = TEXTILE_BODY

    news = News.first
    news.description = TEXTILE_BODY

    document = Document.first
    document.description = TEXTILE_BODY

    message = Message.first
    message.content = TEXTILE_BODY

    custom_field = IssueCustomField.new(name: "Full text", field_format: "text", full_width_layout: "1")
    custom_value = CustomValue.new(custom_field: custom_field, value: TEXTILE_BODY)

    {
      "issue description" => [ issue, :description ],
      "journal notes" => [ journal, :notes ],
      "wiki page" => [ wiki_content, :text ],
      "news" => [ news, :description ],
      "document" => [ document, :description ],
      "forum message" => [ message, :content ],
      "full text custom field" => [ custom_value, :value ]
    }
  end

  # Renders +text+ with the site format set to +format+, so a test can check what
  # a body looks like under both settings.
  #
  # @param format [String] "textile" or "common_mark".
  # @param text [String] the body to render.
  # @return [String] the rendered HTML.
  def render_with_site_format(format, text)
    Setting.text_formatting = format
    textilizable(text)
  end

  context "with the site set to Markdown and a Textile body" do
    should "render Textile everywhere Redmine renders formatted text" do
      formatted_text_holders.each do |label, (object, attribute)|
        html = textilizable(object, attribute)

        assert_match(/<h2[^>]*>Heading/, html, "#{label} was not rendered as Textile")
        assert_match(%r{<a href="https://ex\.com/"[^>]*>link</a>}, html,
                     "#{label} lost its Textile link")
      end
    end
  end

  # FR-021: +**+ says nothing about the format, so a body that only uses it is left
  # to the site setting instead of being pushed to Markdown.
  context "with a body whose only notation is ** and *" do
    setup { @body = "This is an **important** *change*." }

    should "follow the site setting when it is Textile" do
      html = render_with_site_format("textile", @body)

      assert_includes html, "<b>important</b>"
      assert_includes html, "<strong>change</strong>"
      assert_not_includes html, "<em>"
    end

    should "follow the site setting when it is Markdown" do
      html = render_with_site_format("common_mark", @body)

      assert_includes html, "<strong>important</strong>"
      assert_includes html, "<em>change</em>"
    end

    should "still render a Textile document that uses ** as Textile under either setting" do
      body = "h1. Heading\n\nThis is **bold**.\n"

      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, body), "<h1", format
      end
    end
  end

  # FR-021: what an indented code block quotes must not decide the format.
  context "with Textile notation quoted in an indented code block" do
    setup { @body = "Use *care* when quoting the old syntax:\n\n    \"link\":https://ex.com/\n\nEnd.\n" }

    should "follow the site setting when it is Markdown" do
      assert_includes render_with_site_format("common_mark", @body), "<em>care</em>"
    end

    should "follow the site setting when it is Textile" do
      assert_includes render_with_site_format("textile", @body), "<strong>care</strong>"
    end

    should "put the indented block in a pre element under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, @body), "<pre", format
      end
    end
  end

  # FR-021: a table has to come out as a table under either setting.
  context "with a table" do
    should "render a table without a separator row as a table under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, "| Name | Value |\n| a | 1 |\n"), "<table", format
      end
    end

    should "render a table with a separator row as a table under either setting" do
      body = "| Name | Value |\n|---|---|\n| a | 1 |\n"

      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, body), "<table", format
      end
    end

    # A dash in a cell does not make the row a Markdown separator row, so the table
    # stays a Textile one even on a Markdown site.
    should "keep a Textile table with a dash in a cell a table under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, "| - | x |\n| a | b |\n"), "<table", format
      end
    end

    # A single pipe row is too little evidence to name a format, so the detector
    # misses it and the Markdown site renders it as it would any Markdown text. This
    # pins the accepted limit of ADR-0005, not a behaviour worth defending: a
    # detector that learns to read a lone row may change it.
    should "leave a lone pipe row to the site setting" do
      assert_not_includes render_with_site_format("common_mark", "| Name | Value |\n"), "<table"
    end
  end

  # FR-021: an indented block under a Markdown heading is code, so the Textile it
  # quotes must not turn the document into a Textile one.
  context "with an indented code block under a Markdown heading" do
    setup { @body = "## Usage\n\n    \"one\":https://ex.com/\n    \"two\":https://ex.org/\n" }

    should "render the heading and the code block under either setting" do
      %w[textile common_mark].each do |format|
        html = render_with_site_format(format, @body)

        assert_includes html, "<h2", format
        assert_includes html, "<pre", format
        assert_not_includes html, "<a href=\"https://ex.com/\"", format
      end
    end
  end

  # FR-021: notation that only Markdown reads as structure has to render as
  # structure whichever format the site is set to.
  context "with a Markdown list or heading" do
    should "render a dash list as a list under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, "- faster\n- fewer queries\n"), "<ul>", format
      end
    end

    should "render a numbered list as a list under either setting" do
      %w[textile common_mark].each do |format|
        html = render_with_site_format(format, "1. stop the server\n2. migrate the data\n")

        assert_includes html, "<ol>", format
      end
    end

    should "render a Setext heading as a heading under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, "Release notes\n=============\n"), "<h1", format
      end
    end

    # Both formats read this the same way, so detection stays out of it and the
    # site setting alone decides.
    should "render an asterisk list as a list under either setting" do
      %w[textile common_mark].each do |format|
        assert_includes render_with_site_format(format, "* apple\n* orange\n"), "<ul>", format
      end
    end

    # A Textile document with hand-written dashes stays Textile, whatever the site
    # is set to: the dashes are not a list in Textile.
    should "keep a Textile document with a dash list Textile under either setting" do
      body = "h1. Notes\n\n- one\n- two\n- three\n- four\n- five\n"

      %w[textile common_mark].each do |format|
        html = render_with_site_format(format, body)

        assert_includes html, "<h1", format
        assert_not_includes html, "<ul>", format
      end
    end
  end
end

# FR-009 / FR-017 / FR-018: the write side stays on the site format, and preview
# agrees with what the saved page will look like.
class RenderSwitcherWriteSideTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :enabled_modules, :trackers, :issue_statuses, :enumerations, :issues,
           :issue_categories, :versions, :workflows, :custom_fields, :custom_values,
           :custom_fields_trackers, :attachments

  TEXTILE_BODY = %(h2. Heading\n\n"link":https://ex.com/\n)

  def setup
    super
    @original_format = Setting.text_formatting
    @original_settings = Setting.plugin_redmine_render_switcher
    Setting.text_formatting = "common_mark"
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => "1", "score_threshold" => "2" }
    log_user("admin", "admin")
  end

  def teardown
    Setting.text_formatting = @original_format
    Setting.plugin_redmine_render_switcher = @original_settings
    super
  end

  # @return [Boolean] whether the running Redmine is at least the given release.
  def redmine_at_least?(major, minor)
    ([ Redmine::VERSION::MAJOR, Redmine::VERSION::MINOR ] <=> [ major, minor ]) >= 0
  end

  test "preview returns the same verdict the saved page will get" do
    post "/preview/text", params: { text: TEXTILE_BODY }

    assert_response :success
    assert_match(/<h2[^>]*>Heading/, response.body)
    assert_match(%r{<a href="https://ex\.com/"[^>]*>link</a>}, response.body)
  end

  test "the edit form still loads the toolbar of the site format" do
    get "/issues/1/edit"

    assert_response :success
    assert_select "script[src*=?]", "jstoolbar/common_mark"
  end

  # Redmine 6.1 added list-autofill to the wiki textareas and 7.0 added table-paste;
  # 6.0 has neither, so each assertion only runs where the core provides the helper.
  test "the edit form still advertises the site format to the list-autofill helper" do
    skip "list-autofill needs Redmine 6.1" unless redmine_at_least?(6, 1)

    get "/issues/1/edit"

    assert_response :success
    assert_select "textarea[data-list-autofill-text-formatting-param=?]", Setting.text_formatting
  end

  test "the edit form still advertises the site format to the table-paste helper" do
    skip "table-paste needs Redmine 7.0" unless redmine_at_least?(7, 0)

    get "/issues/1/edit"

    assert_response :success
    assert_select "textarea[data-table-paste-text-formatting-param=?]", Setting.text_formatting
  end

  test "the built-in syntax help page still renders" do
    get "/help/wiki_syntax"

    assert_response :success
  end
end
