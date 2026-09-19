# frozen_string_literal: true

require File.expand_path("version", __dir__)
require File.expand_path("lib/redmine_render_switcher/logger", __dir__)
require File.expand_path("lib/redmine_render_switcher/plugin_settings", __dir__)
require File.expand_path("lib/redmine_render_switcher/detector", __dir__)
require File.expand_path("lib/redmine_render_switcher/directive", __dir__)
require File.expand_path("lib/redmine_render_switcher/auto_switch", __dir__)
require File.expand_path("lib/redmine_render_switcher/cache_key", __dir__)

Redmine::Plugin.register :redmine_render_switcher do
  name "Redmine Render Switcher plugin"
  author "Haruyuki Iida"
  description "Renders each text with the formatter that matches how it is actually written, " \
              "so a Textile site can adopt Markdown without converting existing content."
  version RedmineRenderSwitcher::VERSION
  url "https://github.com/haru/redmine_render_switcher"
  author_url "https://github.com/haru"
  requires_redmine version_or_higher: "6.0.0"

  # The partial name carries the plugin name because Redmine warns when two
  # plugins claim the same one.
  settings default: { "auto_detect_enabled" => true, "score_threshold" => 2 },
           partial: "settings/redmine_render_switcher_settings"
end

# Patch the formatters here, directly. Wrapping this in
# Rails.application.config.to_prepare would never fire: the plugin loader already
# re-runs init.rb inside to_prepare, and a nested one is registered too late.
# RedmineRenderSwitcher::AutoSwitch.prepend_to is idempotent by module name, which
# is what makes repeated reloads safe.
[ Redmine::WikiFormatting::Textile::Formatter,
  Redmine::WikiFormatting::CommonMark::Formatter ].each do |formatter|
  RedmineRenderSwitcher::AutoSwitch.prepend_to(formatter)
end

# Second coupling point: the cache key is built before any formatter exists, so
# the detector generation has to be added from here (see ADR-0002 and ADR-0004).
RedmineRenderSwitcher::CacheKey.prepend_to(Redmine::WikiFormatting.singleton_class)
