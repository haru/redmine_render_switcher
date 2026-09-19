---
title: Running lint, YARD and coverage
type: howto
sources: [S001, S002]
updated: 2026-09-19
---

# Running lint, YARD and coverage

## Rubocop

Run it from the plugin directory **without** `bundle exec`:

```bash
rubocop --ignore-parent-exclusion
```

`.rubocop.yml` lists `rubocop-rails`, `rubocop-performance` and
`rubocop-factory_bot` under `plugins:`, but Redmine's bundle contains none of
them, so `bundle exec rubocop` aborts with
`cannot load such file -- rubocop-rails`. The system rubocop (1.91.0) runs
fine. (S001, S002)

CLAUDE.md's statement that the blocker is `rubocop-factory_bot` is out of date;
the unresolved plugin found by measurement is `rubocop-rails`. (S001)

Options rejected: removing `rubocop-rails` from `plugins:` (Rails cops are
enabled on purpose), editing Redmine's `Gemfile` (out of scope), or adding the
gems to the plugin `Gemfile` (re-resolves the whole Redmine bundle with unclear
side effects). (S001)

Leftover `Exclude:` paths under `lib/redmine_ai_helper/**` are harmless and are
deliberately not cleaned up in this feature. (S001)

## YARD

`bundle exec yard stats --list-undoc` works and must stay at 100%. (S001, S002)

## Coverage (SimpleCov)

The C0 target is 90% or more. Without a plugin-only filter, Redmine core is
counted in the denominator and the figure is meaningless, so
`test/test_helper.rb` needs something equivalent to
`SimpleCov.start { add_filter %r{^(?!/?plugins/redmine_render_switcher/lib)} }`. (S001, S002)

## Tests

From `$REDMINE_ROOT`:
`bundle exec rake redmine:plugins:test NAME=redmine_render_switcher`. (S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Constitution gates](./constitution-gates-and-adr-obligations.md)
