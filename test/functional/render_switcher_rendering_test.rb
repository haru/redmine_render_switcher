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
