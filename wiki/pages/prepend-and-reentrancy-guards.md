---
title: Applying the prepend safely — reload and recursion guards
type: howto
sources: [S001, S002]
updated: 2026-09-19
---

# Applying the prepend safely — reload and recursion guards

These are verified constraints, not design options. (S001)

## Where to patch

Patch directly in `init.rb`. Do **not** wrap it in
`Rails.application.config.to_prepare`: a plugin's `init.rb` is itself re-run
inside `to_prepare`, so a nested `to_prepare` never fires. (S001)

## Avoid double prepend

Guard by module **name**:

```ruby
klass.ancestors.any? { |m| m.name == "RedmineRenderSwitcher::AutoSwitch" }
```

After a reload the constant is a different object, so
`ancestors.include?(AutoSwitch)` cannot detect an earlier prepend. (S001)

## Re-entrancy guard

Set a `Thread.current[:redmine_render_switcher_switching]` flag while
delegating. The delegate formatter is patched with the same module, so without
the flag delegation recurses forever. (S001)

## How many patch points

Three `prepend`s in total: both Formatters (`AutoSwitch`) and the singleton
class of `Redmine::WikiFormatting` (`CacheKey`). No core file is edited. (S002)

## Never register the directive as a macro

See [the directive page](./directive-html-comment-form.md). (S001)

## See also

[Overview](./auto-format-detection-overview.md) ·
[AutoSwitch](./auto-switch-module.md) ·
[Why formatters are patched](./why-patch-formatters-not-register-format.md) ·
[Cache key](./cache-key-detector-version.md)
