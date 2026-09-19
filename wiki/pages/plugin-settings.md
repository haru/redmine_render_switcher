---
title: Plugin settings
type: component
sources: [S001, S002]
updated: 2026-09-19
---

# Plugin settings

## Declaration

`init.rb` declares Redmine's official plugin settings:

```ruby
settings default: { "auto_detect_enabled" => true, "score_threshold" => 2 },
         partial: "settings/redmine_render_switcher_settings"
```

Values are stored in `Setting.plugin_redmine_render_switcher` and read only
through `RedmineRenderSwitcher::PluginSettings`. (S001, S002)

## Rules

- Only two settings exist: enable/disable and the score threshold. There is no
  default-format setting. (S002)
- Because `:default` supplies values before anything is saved, the code needs no
  `nil` fallback (Constitution III). (S001)
- The settings form saves **strings**. Normalising `"0"`, `""` and `"1"` and
  converting `score_threshold` to an integer happens in one place,
  `PluginSettings`. (S001)
- The partial lives at
  `app/views/settings/_redmine_render_switcher_settings.html.erb`. Its name
  includes the plugin name because core warns on partial-name collisions
  (`plugin.rb:124-131`). (S001)
- No table or extra `Setting` keys: that would add migrations, which the spec
  excludes. (S001, S002)
- Effect of disabling: see [AutoSwitch](./auto-switch-module.md) and the
  [cache key](./cache-key-detector-version.md). (S001)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Detector design](./detector-design.md)
