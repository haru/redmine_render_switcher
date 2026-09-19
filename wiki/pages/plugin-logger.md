---
title: Plugin logger
type: component
sources: [S001, S002]
updated: 2026-09-19
---

# Plugin logger

## Decision

Add `RedmineRenderSwitcher::Logger` in `lib/redmine_render_switcher/logger.rb`.
It is a mixin; classes `include` it and log only through
`render_switcher_logger`. (S001)

## Why

CLAUDE.md and Constitution principle V forbid calling `Rails.logger` directly.
The logger CLAUDE.md names, `RedmineAiHelper::Logger` / `ai_helper_logger`,
belongs to a different plugin and does not exist in this repository, so an
equivalent module is created in this plugin's namespace. (S001, S002)

## Behaviour

- Debug level only (FR-021). Every detection logs the chosen format, the textile
  score, the markdown score and the reason. (S001)
- Use the block form, `debug { ... }`, so the message is not built when debug
  logging is off. (S001)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Detector design](./detector-design.md) ·
[Constitution gates](./constitution-gates-and-adr-obligations.md)
