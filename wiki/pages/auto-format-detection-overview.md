---
title: Auto format detection — overview
type: concept
sources: [S001, S002]
updated: 2026-09-19
---

# Auto format detection — overview

The plugin renders each text field as Textile or Markdown according to its
*content*, without changing `Setting.text_formatting`. A site with historical
Textile content can therefore write new content in Markdown (or the reverse)
without converting anything. (S002)

## How it works

- **Approach B**: one module, `AutoSwitch`, is prepended to both
  `Textile::Formatter` and `CommonMark::Formatter` and delegates to the *other*
  formatter only when detection disagrees with the site setting. See
  [why formatters are patched](./why-patch-formatters-not-register-format.md)
  and [AutoSwitch](./auto-switch-module.md). (S001, S002)
- **Two-stage detection**: an explicit first-line
  [directive](./directive-html-comment-form.md) wins, then the scoring
  [detector](./detector-design.md). If the score gap is below the threshold,
  nothing is delegated and the site setting's formatter renders. (S002)
- A [cache-key patch](./cache-key-detector-version.md) stops stale HTML being
  reused from Redmine's formatted-text cache after the detector changes. (S002)
- Section-edit links only work if rendering and section editing agree on the
  format: see [section numbering](./section-numbering-consistency.md). (S001)

## Scope

- No migration, controller or model, and no core file edits. The only stored
  state is [plugin settings](./plugin-settings.md) with two keys. (S002)
- Deliberately not built: rake tasks, an admin screen, a mixed-format detection
  UI, and persisting the detection result at save time. (S002)
- Mixed formats inside one field are unsupported and must be documented
  (FR-024). (S002)
- Stored text is never modified (FR-007). (S002)

## Planned layout

`init.rb` (registration, settings, three `prepend`s) plus
`lib/redmine_render_switcher/` holding `logger.rb`, `plugin_settings.rb`,
`directive.rb`, `detector.rb`, `auto_switch.rb` and `cache_key.rb`; one settings
partial; `en`/`ja` locales; ADRs and `docs/directive-usage.md`. (S002)

## Performance target

Detection must cost under 5% of a render (SC-003). Baseline: 0.286 ms
detection against 13.7 ms Textile and 47.7 ms CommonMark rendering. (S002)

## Related

[Prepend pitfalls](./prepend-and-reentrancy-guards.md) ·
[Logger](./plugin-logger.md) ·
[Lint and coverage tooling](./lint-and-coverage-tooling.md) ·
[Constitution gates](./constitution-gates-and-adr-obligations.md)
