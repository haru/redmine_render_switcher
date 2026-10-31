---
title: Constitution gates and ADR obligations
type: concept
sources: [S001, S002, S004, S005, S006]
updated: 2026-10-31
---

# Constitution gates and ADR obligations

The plan checks the feature against the project constitution (v1.1.0,
`.specify/memory/constitution.md`) in two passes, before Phase 0 and after
Phase 1 design. The file is authoritative; this page summarises how it applied.
(S002)

## Principles as applied

| Principle | What it demands here |
|---|---|
| I. Minimal Core Surface | Depend only on the Formatter contract, never `@filter`. Every new `prepend` needs an ADR. |
| II. Test-First | Failing test before implementation; the detector is table-driven; C0 ≥ 90%. |
| III. Errors Surface Immediately | No fallback `rescue`. Defaults come from plugin settings `:default`, not `nil` guards. |
| IV. Explainable, Versioned, Overridable | `Detector::Result` with a reason, `VERSION` in the cache key, directive has top priority, detection is non-destructive. |
| V. Quality Gates | C0 ≥ 90%, YARD 100%, rubocop 0 offenses, no `Rails.logger`. |
| VI. KISS / DRY / YAGNI | Two settings only, one frozen rule table, one format-name convention. |

(S002)

## Outcome

Principle I is the only conditional pass. The plan adds two coupling points, so
it owes **ADR-0001** ([formatter patching](./why-patch-formatters-not-register-format.md))
and **ADR-0002** ([cache key](./cache-key-detector-version.md)). The design
phase found no third coupling point and no `rescue` site. (S001, S002)

## Detector rule revision (feature 002)

The revision adds no `prepend` and no patched core class, so Principle I passes
without a coupling-point ADR. FR-002 still requires **ADR-0005** for the scoring
policy; block scoring and the two-line list floor go in its Consequences, and
whether they deserve an ADR of their own is put to the user, not decided
unilaterally. No `rescue` is added (Principle III). (S004)

## Textile insertion scoring (bugfix 003)

One constant and one table row, so there is no new `prepend` and Principle I
passes without a coupling-point ADR. Principle IV asks for ambiguity to be solved
by context rules rather than patterns; `+` is decided by the characters around one
notation and never across lines, so a bounded pattern like `TEXTILE_INLINE_CODE`
suffices and no scan is added. No `rescue` or encoding guard is added (Principle
III), and the inline-code masking is rejected under Principle VI. The decision is
recorded in **ADR-0006** (created with the change); `Detector::VERSION` goes to 6.
See [insertion scoring](./detector-textile-insertion.md). (S005, S006)

## Work the gates commit to

`config/locales/ja.yml`, the [plugin logger](./plugin-logger.md),
`docs/adr/README.md` (updated in the same change as each ADR), the SimpleCov
plugin-only filter, and fixing the existing `Style/StringLiterals` offense at
`test/test_helper.rb:2`. See [tooling](./lint-and-coverage-tooling.md) for how to
run the checks. (S001, S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[Plugin settings](./plugin-settings.md)
