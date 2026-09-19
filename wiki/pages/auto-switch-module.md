---
title: AutoSwitch — the prepended formatter module
type: component
sources: [S001, S002]
updated: 2026-09-19
---

# AutoSwitch — the prepended formatter module

## Contract surface

- Defines exactly five methods: `initialize(text, options = {})`, `to_html`,
  `extract_sections`, `get_section`, `update_section`. It never touches `@filter`
  or other formatter internals. (S001, S002)
- The methods come from different places in each formatter, but `prepend` wins
  over both. `CommonMark::Formatter` gets its section methods from
  `SectionHelper`. `Textile::Formatter` also includes `SectionHelper` but
  redefines `extract_sections` with `def_delegators :@filter`
  (`textile/formatter.rb:32-33`). `get_section` / `update_section` come from
  `SectionHelper` in both and call `extract_sections` internally. (S001)
- Rejected: blanket delegation through `method_missing`. Dynamic dispatch is not
  justified under KISS and would delegate methods outside the contract. (S001)

## Behaviour

1. The [directive](./directive-html-comment-form.md) is evaluated first, then
   the [detector](./detector-design.md). (S002)
2. Detection runs once per instance and is memoized, so `to_html` and
   `extract_sections` never disagree
   ([why](./section-numbering-consistency.md)). (S001, S002)
3. It delegates to the other formatter only when the result differs from the
   site setting. If the score gap is under the threshold it returns `super`.
   That is designed normal-path behaviour and must not be written as a
   `rescue`. (S002)
4. When `auto_detect_enabled` is false it returns `super` immediately, with no
   detection and no delegation, so output is identical to a site without the
   plugin (FR-019, SC-005). Rejected: making the `prepend` itself conditional,
   because changing the class hierarchy on every settings change interacts
   unpredictably with code reloading. (S001)
5. Each detection is logged at debug level via the
   [plugin logger](./plugin-logger.md). (S001)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Prepend pitfalls](./prepend-and-reentrancy-guards.md) ·
[Plugin settings](./plugin-settings.md) ·
[Cache key](./cache-key-detector-version.md)
