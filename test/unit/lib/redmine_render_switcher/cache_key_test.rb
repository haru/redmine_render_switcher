# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

# FR-022: a formatted-HTML cache entry must not outlive the detection logic that
# produced it. Redmine's own key holds only the format name and a digest of the
# text, and the cache lookup happens before any formatter is built, so the
# detector's generation has to be added here rather than inside the formatter.
class RedmineRenderSwitcherCacheKeyTest < ActiveSupport::TestCase
  fixtures :projects, :users, :email_addresses, :trackers, :issue_statuses,
           :enumerations, :issues, :roles, :members, :member_roles, :enabled_modules

  BIG_TEXT = "x" * 3000

  def setup
    @original_settings = Setting.plugin_redmine_render_switcher
    @issue = Issue.find(1)
  end

  def teardown
    Setting.plugin_redmine_render_switcher = @original_settings
  end

  def enable_auto_detect(enabled)
    Setting.plugin_redmine_render_switcher =
      { "auto_detect_enabled" => enabled ? "1" : "0", "score_threshold" => "2" }
  end

  # The key Redmine would build with this plugin not installed.
  def core_cache_key_for(*args)
    Redmine::WikiFormatting
      .singleton_class
      .instance_method(:cache_key_for)
      .super_method
      .bind_call(Redmine::WikiFormatting, *args)
  end

  # Runs the block with Detector::VERSION temporarily set to another generation.
  def with_detector_version(version)
    original = RedmineRenderSwitcher::Detector::VERSION
    RedmineRenderSwitcher::Detector.send(:remove_const, :VERSION)
    RedmineRenderSwitcher::Detector.const_set(:VERSION, version)
    yield
  ensure
    RedmineRenderSwitcher::Detector.send(:remove_const, :VERSION)
    RedmineRenderSwitcher::Detector.const_set(:VERSION, original)
  end

  context "RedmineRenderSwitcher::CacheKey#cache_key_for" do
    # K-01
    should "append the detector generation and the threshold to the key" do
      enable_auto_detect(true)

      key = Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, @issue, "description")

      assert key.end_with?("-rs#{RedmineRenderSwitcher::Detector::VERSION}t2"), key
      assert key.start_with?(core_cache_key_for("textile", BIG_TEXT, @issue, "description")), key
    end

    # K-02
    should "produce a different key for a different detector generation" do
      enable_auto_detect(true)
      current = Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, @issue, "description")

      bumped = with_detector_version(RedmineRenderSwitcher::Detector::VERSION + 1) do
        Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, @issue, "description")
      end

      assert_not_equal current, bumped
    end

    # K-03
    should "return nil when there is no object" do
      enable_auto_detect(true)

      assert_nil Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, nil, "description")
    end

    # K-04
    should "return nil for a record that has not been saved" do
      enable_auto_detect(true)

      assert_nil Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, Issue.new, "description")
    end

    # K-07: the threshold decides a verdict just as much as the detector code does,
    # so an entry cached under one threshold must not be served under another. Core
    # caches formatted text with no expiry, so a surviving entry survives for good.
    should "produce a different key for a different threshold" do
      keys = [ 2, 7 ].map do |threshold|
        Setting.plugin_redmine_render_switcher =
          { "auto_detect_enabled" => "1", "score_threshold" => threshold.to_s }
        Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, @issue, "description")
      end

      assert_not_equal keys.first, keys.last
    end

    # K-08: the same settings must keep producing the same key, or nothing is ever
    # a cache hit.
    should "produce a stable key while the settings do not change" do
      enable_auto_detect(true)
      args = [ "textile", BIG_TEXT, @issue, "description" ]

      assert_equal Redmine::WikiFormatting.cache_key_for(*args),
                   Redmine::WikiFormatting.cache_key_for(*args)
    end

    # K-05
    should "return exactly the core key when auto-detection is off" do
      enable_auto_detect(false)

      assert_equal core_cache_key_for("textile", BIG_TEXT, @issue, "description"),
                   Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, @issue, "description")
      assert_nil Redmine::WikiFormatting.cache_key_for("textile", BIG_TEXT, Issue.new, "description")
    end
  end

  context "RedmineRenderSwitcher::CacheKey installation" do
    # K-06
    should "stay applied exactly once however often it is installed" do
      singleton = Redmine::WikiFormatting.singleton_class

      3.times { RedmineRenderSwitcher::CacheKey.prepend_to(singleton) }

      count = singleton.ancestors.count { |m| m.name == "RedmineRenderSwitcher::CacheKey" }

      assert_equal 1, count
    end
  end
end
