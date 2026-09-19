---
title: Why patch the formatters instead of registering a format
type: decision
sources: [S001, S002]
updated: 2026-09-19
---

# Why patch the formatters instead of registering a format

## Decision

Approach B: prepend the same module to `Redmine::WikiFormatting::Textile::Formatter`
and `Redmine::WikiFormatting::CommonMark::Formatter`, and delegate internally to
the other side. `Setting.text_formatting` keeps its normal values (`textile` /
`common_mark`). It was verified against a real Redmine 7.0.1 (feasibility
report, chapter 10). (S001, S002)

## Rejected: Approach A

Registering a new `auto` format through the official `wiki_format_provider` API
needs no core patching, but `Setting.text_formatting` then holds a value Redmine
does not know. Eight unrelated places break and each needs its own patch: the
help templates (a 500 if missing), `data-text-formatting`, jstoolbar, Stimulus
params, and two spots in `mail_handler`, among others. Each must also be
re-checked on every Redmine upgrade. (S001, S002)

## Consequences

- With B those eight patches are unnecessary except the cache key, so what has
  to track Redmine collapses to the Formatter contract alone. (S001, S002)
- The cost is a new coupling point: prepending onto core classes. Constitution
  principle I requires an ADR for that, hence **ADR-0001**
  (`docs/adr/0001-patch-formatters-instead-of-registering-a-format.md`). (S001, S002)
- The cache key needs a *second* coupling point, which is why
  [ADR-0002](./cache-key-detector-version.md) exists. (S002)
- Extension-driven rendering (for example repository browsing) also passes
  through the patched formatters. This was accepted. (S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[AutoSwitch](./auto-switch-module.md) ·
[Prepend pitfalls](./prepend-and-reentrancy-guards.md) ·
[Constitution gates](./constitution-gates-and-adr-obligations.md)
