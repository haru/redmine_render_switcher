# ADR-0004: Add the score threshold to the formatted-text cache key

- **Status**: Accepted
- **Date**: 2026-09-19

## Context

ADR-0002 put the detector's generation into Redmine's formatted-HTML cache key by
appending `-rs#{Detector::VERSION}`, on the reasoning that a correction to the
detector has to become visible on the pages it affects. Its Decision names the
version as the only addition.

That reasoning stops one input short. The verdict for a text is decided by the
detection code *and* by `score_threshold`, and the threshold is a plugin setting an
administrator can change at any time. Raising or lowering it moves texts across the
line between "detected format" and "the site format", so it changes rendered output
exactly as a detector change does. Redmine caches formatted text with no expiry, so a
cache entry left behind by a threshold change is served indefinitely, and nothing in
the key told the two apart.

The code was corrected in commit `7c957bf` to append the threshold as well, so
`CacheKey#cache_key_for` now returns

```
<core key>-rs<Detector::VERSION>t<PluginSettings.score_threshold>
```

ADR-0002 was left as written, as its own rules require, and therefore no longer
describes what the code does. This ADR restates the decision so that the current
behaviour has a record.

## Decision

Prepend `RedmineRenderSwitcher::CacheKey` to the singleton class of
`Redmine::WikiFormatting`, overriding `cache_key_for` to call `super` and append
`-rs#{Detector::VERSION}t#{PluginSettings.score_threshold}` to the result.

The two parts answer different questions and are maintained differently:

- `Detector::VERSION` names the generation of the detection *code*. It is bumped in
  the same change as anything that can move a verdict — the pattern tables, the
  line-context rule, code-block masking, the threshold comparison, or the directive
  pattern. Forgetting to is a defect.
- The threshold is *data*, not code, so nobody bumps it. Reading it from
  `PluginSettings` at key-building time makes a change take effect on the next
  render with no action from anyone.

The three properties ADR-0002 recorded are unchanged:

- The first half of the key is never rebuilt; whatever core produced is extended.
- A `nil` from `super` is returned as `nil`. Redmine returns `nil` to say a text is
  not to be cached at all, which is an ordinary outcome and not a failure.
- When auto-detection is switched off, `super` is returned untouched, with no suffix,
  so a disabled plugin is byte-identical to an uninstalled one.

This supersedes [ADR-0002](./0002-add-detector-version-to-formatted-text-cache-key.md).
Everything ADR-0002 says about why the cache key is a coupling point, and about the
alternatives it rejected, still holds and applies here unchanged.

## Alternatives considered

**Keep the version alone and tell administrators to clear the cache after changing the
threshold.** Rejected for the same reason ADR-0002 rejected it for detector changes:
correctness would depend on an undocumented manual step, and nothing signals when it
is needed.

**Fold the threshold into `Detector::VERSION`.** Rejected. The version is a constant
edited by a developer, and the threshold is a value edited by an administrator at
runtime; they cannot share one integer.

**Hash the whole plugin configuration into the key.** Rejected. The plugin has one
setting that can alter a verdict, so a generic digest would hide which input matters
and would invalidate the cache when an unrelated setting is added later.

## Consequences

Changing `score_threshold` leaves the entries rendered under the old value in the
cache, unreachable, and renders large texts afresh under the new one. That is the
intended cost, and it is bounded by how rarely the setting changes.

Distinct thresholds get distinct entries, so switching back to a previous value finds
the earlier entries again instead of re-rendering.

`test/unit/lib/redmine_render_switcher/cache_key_test.rb` pins both halves of the
suffix and the switched-off case.

## Note on the record

ADR-0001 says its measurements are in `docs/feasibility.md`. That file was never
committed, so the measurements are not in the repository. ADR-0001's decision does not
rest on them alone: its reasons — the number of places the name of a registered format
leaks into Redmine core — can be re-established by reading `app/` and `lib/` of the
Redmine checkout and by probing with `bin/rails runner`. Read the `docs/feasibility.md`
references in ADR-0001 as pointing at evidence that is no longer available, not as a
document to look for.
