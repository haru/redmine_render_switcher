require File.expand_path("version", __dir__)

Redmine::Plugin.register :redmine_render_switcher do
  name 'Redmine Render Switcher plugin'
  author 'Author name'
  description 'This is a plugin for Redmine'
  version RedmineRenderSwitcher::VERSION
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'
end
