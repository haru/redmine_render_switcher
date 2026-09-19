---
title: Detector version in the formatted-text cache key
type: decision
sources: [S001, S002]
updated: 2026-09-19
---

# Detector version in the formatted-text cache key

## The problem

`Redmine::WikiFormatting.cache_key_for(format, text, object, attribute)`
(`lib/redmine/wiki_formatting.rb:89-114`) returns
`formatted_text/<format>/<model>/<id>-<attr>-<digest>` only when `object` and
`attribute` are present, the record is persisted and `format` is present;
otherwise it returns `nil`. (S001)

The key holds only the format name and a text digest, never the detector's
generation. The cache applies when `Setting.cache_formatted_text?` is on and the
text exceeds 2 KB, and that check runs *before* a Formatter is created. So the
Formatter contract cannot reach it. After a detector fix, old HTML would keep
being served. (S001, S002)

## Decision

Prepend a `CacheKey` module to the **singleton class** of
`Redmine::WikiFormatting`:

- if `super` returns `nil`, return `nil`;
- otherwise append `-rs#{Detector::VERSION}t#{PluginSettings.score_threshold}` to
  the string. The version covers the detection code; the threshold covers the one
  input to the same verdict that an administrator can change at runtime, so
  changing it must also invalidate cached HTML.

It appends to `super` rather than rebuilding the key, and uses no `rescue`; the
`nil` branch is the normal path. (S001, S002)

When `auto_detect_enabled` is false, no version is appended, so keys equal the
core's and the site behaves exactly as without the plugin (SC-005). See
[AutoSwitch](./auto-switch-module.md). (S001)

## Rejected alternatives

A plugin-owned cache, disabling `cache_formatted_text`, or asking admins to
flush the cache by hand. Each either fails FR-022 (automatic invalidation) or
breaks existing Redmine behaviour. (S001, S002)

## Record

This is the second coupling point, so **ADR-0002**
(`docs/adr/0002-add-detector-version-to-formatted-text-cache-key.md`) is
required by Constitution principle I. The threshold half of the key was added
afterwards and is recorded in **ADR-0004**
(`docs/adr/0004-add-score-threshold-to-formatted-text-cache-key.md`), which
supersedes ADR-0002. (S001, S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Why formatters are patched](./why-patch-formatters-not-register-format.md) ·
[Detector design](./detector-design.md) (owns `VERSION`) ·
[Plugin settings](./plugin-settings.md)
