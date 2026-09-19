# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherPluginSettingsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :trackers, :issue_statuses,
           :enumerations, :issues, :roles, :members, :member_roles, :enabled_modules

  TEXTILE_BODY = %(h2. みだし\n\n"link":https://ex.com/\n)
  MARKDOWN_BODY = %(## みだし\n\n[link](https://ex.com/)\n)

  # Renders the way Redmine would with this plugin not installed.
  def core_to_html(format, text)
    klass = Redmine::WikiFormatting.formatter_for(format)
    klass.instance_method(:to_html).super_method.bind_call(klass.new(text))
  end

  def core_cache_key_for(*args)
    Redmine::WikiFormatting
      .singleton_class
      .instance_method(:cache_key_for)
      .super_method
      .bind_call(Redmine::WikiFormatting, *args)
  end

  # Flattens a locale file into the set of its leaf keys.
  def locale_keys(path)
    flatten_keys(YAML.load_file(path).values.first)
  end

  def flatten_keys(node, prefix = "")
    return [ prefix ] unless node.is_a?(Hash)

    node.flat_map { |key, value| flatten_keys(value, prefix.empty? ? key.to_s : "#{prefix}.#{key}") }
  end

  context "RedmineRenderSwitcher::PluginSettings" do
    setup do
      @original_settings = Setting.plugin_redmine_render_switcher
    end

    teardown do
      Setting.plugin_redmine_render_switcher = @original_settings
    end

    # S-01
    should "fall back to the declared defaults when nothing has been saved" do
      Setting.where(name: "plugin_redmine_render_switcher").delete_all
      Setting.clear_cache

      assert_equal true, RedmineRenderSwitcher::PluginSettings.auto_detect_enabled?
      assert_equal 2, RedmineRenderSwitcher::PluginSettings.score_threshold
    end

    # S-02
    should "read the unchecked checkbox value as disabled" do
      Setting.plugin_redmine_render_switcher = { "auto_detect_enabled" => "0" }

      assert_equal false, RedmineRenderSwitcher::PluginSettings.auto_detect_enabled?
    end

    # S-03
    should "read the checked checkbox value as enabled" do
      Setting.plugin_redmine_render_switcher = { "auto_detect_enabled" => "1" }

      assert_equal true, RedmineRenderSwitcher::PluginSettings.auto_detect_enabled?
    end

    # S-04
    should "read the threshold as an Integer" do
      Setting.plugin_redmine_render_switcher = { "score_threshold" => "5" }

      threshold = RedmineRenderSwitcher::PluginSettings.score_threshold

      assert_equal 5, threshold
      assert_kind_of Integer, threshold
    end
  end

  context "with auto-detection switched off" do
    setup do
      @original_format = Setting.text_formatting
      Setting.plugin_redmine_render_switcher =
        { "auto_detect_enabled" => "0", "score_threshold" => "2" }
    end

    teardown do
      Setting.text_formatting = @original_format
    end

    # S-05
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

    # S-06
    should "build exactly the core cache key" do
      args = [ "textile", "x" * 3000, Issue.find(1), "description" ]

      assert_equal core_cache_key_for(*args), Redmine::WikiFormatting.cache_key_for(*args)
    end
  end

  context "the settings partial" do
    # S-07
    should "render from the locale files in both languages" do
      english = render_settings_partial(:en)
      japanese = render_settings_partial(:ja)

      assert_includes english, I18n.t("redmine_render_switcher.settings.auto_detect_enabled", locale: :en)
      assert_includes japanese, I18n.t("redmine_render_switcher.settings.auto_detect_enabled", locale: :ja)
      assert_not_equal english, japanese, "the partial must not hardcode its wording"
      assert_includes english, "settings[auto_detect_enabled]"
      assert_includes english, "settings[score_threshold]"
    end

    should "contain no JavaScript" do
      assert_not_includes render_settings_partial(:en), "<script"
    end
  end

  context "the locale files" do
    # S-08
    should "define the same keys in English and in Japanese" do
      root = File.expand_path("../../../..", __dir__)

      assert_equal locale_keys(File.join(root, "config", "locales", "en.yml")).sort,
                   locale_keys(File.join(root, "config", "locales", "ja.yml")).sort
    end
  end

  def render_settings_partial(locale)
    I18n.with_locale(locale) do
      ApplicationController.render(
        partial: "settings/redmine_render_switcher_settings",
        locals: { settings: Setting.plugin_redmine_render_switcher }
      )
    end
  end
end
