# ADR-0002: Add the detector version to the formatted-text cache key

- **Status**: Superseded by [ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md)
- **Date**: 2026-09-19

## Context

Detection is a heuristic, so it will be wrong sometimes and will be corrected over
the life of the plugin. A correction has to become visible on the pages it affects;
otherwise fixing a misdetection is indistinguishable from not fixing it.

Redmine caches rendered HTML. `Redmine::WikiFormatting.to_html` consults the cache
when `Setting.cache_formatted_text?` is on and the text is larger than 2 kilobytes,
and the key comes from `cache_key_for`
(`lib/redmine/wiki_formatting.rb`, verified against the 7.0.1 checkout):

```ruby
def cache_key_for(format, text, object, attribute)
  if object && attribute && !object.new_record? && format.present?
    "formatted_text/#{format}/#{object.class.model_name.cache_key}/#{object.id}-#{attribute}-#{ActiveSupport::Digest.hexdigest text}"
  end
end
```

The key holds the format name and a digest of the text, and nothing about how the
text was interpreted. Neither changes when the detector changes, so after a scoring
fix, every large cached page keeps serving HTML produced by the old rules until
something else edits it.

The cache lookup happens *before* any formatter is constructed, so this is out of
reach from inside the formatter contract that ADR-0001 confined the plugin to. This
is therefore a second coupling point, and Principle I requires an ADR for it.

## Decision

Prepend `RedmineRenderSwitcher::CacheKey` to the singleton class of
`Redmine::WikiFormatting`, overriding `cache_key_for` to call `super` and append
`-rs#{RedmineRenderSwitcher::Detector::VERSION}` to the result.

`Detector::VERSION` is an integer that names the generation of the detection logic.
Any change to the pattern table, the line-context rule or code-block masking must
bump it in the same change set; not bumping it is a defect, because it silently
keeps the old rendering alive.

Three properties of the override matter:

- The first half of the key is never rebuilt. Whatever core produced is what gets
  extended, so a future change to Redmine's key format is inherited rather than
  fought.
- A `nil` from `super` is returned as `nil`. Redmine returns `nil` to say this text
  is not to be cached at all — a new record, for instance — and that is an ordinary
  outcome of building a key, not a failure to paper over.
- When auto-detection is switched off, `super` is returned untouched, with no
  suffix. Disabling the plugin has to produce byte-identical behaviour to not having
  it installed, and that includes the cache key; otherwise a disabled plugin would
  still invalidate the site's existing cache entries.

## Alternatives considered

**Leave the cache alone and tell administrators to clear it after an upgrade.**
Rejected. It makes correctness depend on someone remembering an undocumented step,
and there is no signal that tells them when it is needed.

**Keep a separate plugin-owned cache keyed on the detection result.** Rejected. It
duplicates machinery Redmine already has and adds a second cache to reason about,
for no gain over adding four characters to the existing key.

**Disable `cache_formatted_text` while the plugin is installed.** Rejected. It takes
away a feature the site chose, and makes large pages slower for everyone to solve a
problem that only appears when the detector changes.

**Reach the cache key from inside the formatter.** Not possible. The cache decision
is made before `formatter_for(format).new(...)` runs, so no code inside the
formatter contract is on that path.

## Consequences

Bumping `Detector::VERSION` invalidates every cached rendering at once. That is the
intended behaviour and the cost is a one-off re-render of large texts, not a
correctness problem.

The plugin now has two coupling points instead of one, and the second depends on a
method that Redmine could rename or restructure. It is a single method and the
override only appends to what `super` returns, so the blast radius is small, but
`cache_key_for` joins the formatter contract on the list of things to re-verify on a
Redmine upgrade. `test/unit/lib/redmine_render_switcher/cache_key_test.rb` covers
this, including the case where the plugin is switched off and the key must match
core's exactly.

Like `AutoSwitch`, this module is applied from `init.rb` and guarded by module name,
for the same reloading reason recorded in ADR-0001.
