---
title: Explicit directive — HTML comment form only
type: decision
sources: [S001, S002]
updated: 2026-09-19
---

# Explicit directive — HTML comment form only

## Decision

A field may force its format with `<!-- render_switcher: textile -->` or
`<!-- render_switcher: markdown -->` on the first line (FR-012). The directive
is checked before the scoring [detector](./detector-design.md), so it always
wins. No stripping code is written. (S001, S002)

`markdown` is translated to Redmine's `common_mark` inside `Directive` only; the
rest of the plugin uses `"textile"` / `"common_mark"` / `nil`. (S002)

## Why it needs no stripping

Measured by feeding both formatters directly: neither output contains the string
`render_switcher`, because both sanitizers drop HTML comments. That removes two
problems at once: the cost of stripping, and the section-edit bug where
`update_section` rebuilt the body from stripped text and deleted the directive
line on every save. `update_section` keeps the directive line (FR-016). (S001)

## Rejected: `{{render_switcher_*}}` macro form

- Registered as a macro, `catch_macros` replaces it with `{{macro(0)}}` before
  rendering, destroying the string the detector must read.
- Not registered, it shows on screen, so it must be stripped, and stripping makes
  `update_section` delete the line each time. (S001)

## Gotcha: blank line after the directive

In Textile, `extract_sections` (`textile/formatter.rb:100`) only recognises a
heading after `\A` or a blank line. If the directive is followed directly by
`h2. A`, that first heading is not counted and `get_section(1)` returns the
*second* section. This is stock Redmine Textile behaviour, not plugin-caused
(any first line does it), but the directive creates the situation. CommonMark is
unaffected. (S001)

Adopted: the documented syntax requires a blank line after the directive
(`docs/directive-usage.md` and the settings help text), the plugin does not
patch the text, and tests pin both layouts. Rejected: inserting the blank line
(violates FR-007 and revives the two-instance problem) and patching Textile's
`extract_sections` (depends on `@filter`). (S001)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Section numbering](./section-numbering-consistency.md) ·
[AutoSwitch](./auto-switch-module.md) ·
[Prepend pitfalls](./prepend-and-reentrancy-guards.md)
