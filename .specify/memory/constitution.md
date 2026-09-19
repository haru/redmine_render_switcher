<!--
Sync Impact Report
==================
Version change: 1.0.0 → 1.1.0
Rationale: MINOR. One principle added and several existing principles/sections materially
expanded with new, measurable obligations. No principle was removed or redefined
incompatibly, so no MAJOR bump.

Modified principles:
  - II. Test-First (NON-NEGOTIABLE) — unchanged title; added a measurable C0 (line)
    coverage floor of 90% with the concrete command that verifies it.
  - III. Errors Surface Immediately (NON-NEGOTIABLE) — unchanged title; added the
    "no easy fallback" formulation and the rule that a caught error must be re-raised,
    logged-and-raised, or converted to a different error — never absorbed.
  - VI. Simplicity: KISS, DRY, YAGNI — NEW principle.

Modified sections:
  - Development Workflow — git-flow branch set completed (release/, hotfix/ added);
    docs/ discovery-by-filename and naming rule added; ADR rule expanded with the
    docs/adr/README.md index, the "ask the user when unsure" rule, and the explicit
    "every significant design decision" trigger.
  - Quality Gates (Principle V) — coverage gate cross-referenced.

Added sections: none (no new top-level headings)
Removed sections: none

Follow-up TODOs: none deferred as placeholders. Two tooling gaps are named in the
summary rather than encoded as TODO tokens: docs/adr/README.md does not exist yet, and
SimpleCov needs a plugin-scoped filter for the 90% figure to be meaningful.

This report is scratch material for review of the amendment and is expected to be
removed before the amended constitution is committed.
-->

# redmine_render_switcher Constitution

## Core Principles

### I. Minimal Core Surface (NON-NEGOTIABLE)

The plugin MUST couple to Redmine through the narrowest contract that achieves the goal.
Concretely, it depends on the Formatter contract only — `initialize(text, options = {})`,
`to_html`, `extract_sections`, `get_section`, `update_section` — and MUST NOT touch
formatter internals such as `@filter`, fork core files, or introduce patches that ripple
into help templates, jstoolbar, drag-and-drop JavaScript, Stimulus params, or
`mail_handler`. `Setting.text_formatting` MUST keep a value Redmine already understands
(`textile` or `common_mark`); the plugin MUST NOT register a new format name.

Any change that widens the coupling surface — a new `prepend`, a new patched core class,
a new dependency on a Redmine internal — requires an ADR recording what broke without it
and what must be re-verified on the next Redmine upgrade.

**Rationale:** The feasibility report measured the alternative: registering an `auto`
format leaks the name into roughly eight unrelated places, each needing its own patch and
re-verification every upgrade. One contract is maintainable; eight coupling points are not.

### II. Test-First (NON-NEGOTIABLE)

Tests are written before the implementation they cover, and MUST fail before they pass.
The detector is table-driven: each Textile/Markdown sample is a row with an expected
verdict, seeded from the samples in `docs/feasibility.md`. Every bug fix begins with a
failing test that reproduces it.

Tests live under `test/unit/` (classes), `test/unit/lib/` (lib classes),
`test/functional/` (controllers), and `test/integration/` (API), and run green via
`bundle exec rake redmine:plugins:test NAME=redmine_render_switcher` from `$REDMINE_ROOT`
before any work is called complete. Mocking is reserved for external servers; the
detector and formatter paths are exercised for real.

**C0 coverage MUST be at least 90%.** C0 is line coverage, measured over the plugin's own
Ruby sources with SimpleCov:

```bash
cd /usr/local/redmine && COVERAGE=1 bundle exec rake redmine:plugins:test NAME=redmine_render_switcher
```

A change that drops coverage below 90% is not complete. Coverage MUST NOT be raised by
tests that execute code without asserting on it — a line is covered when a test would fail
if that line were wrong.

**Rationale:** Detection accuracy is the product. A scoring change silently alters how
existing issues render, and only a dense regression suite makes that change visible before
users see it. The 90% floor makes "dense" a number rather than an opinion.

### III. Errors Surface Immediately (NON-NEGOTIABLE)

Easy fallbacks are forbidden. An error is treated as an error: no `rescue` that swallows
and continues, no silent default on failure, no defensive `nil` guard that hides a broken
assumption, no "render something anyway" path. Errors propagate.

Where an error is caught at all, the handler MUST re-raise it, log and re-raise it, or
raise a more meaningful error in its place. Absorbing it is not an option.

One case is explicitly NOT an exception to this rule: when detection is inconclusive,
`AutoSwitch` returns `super` — rendering with the formatter the site setting already
chose. That is the designed outcome of a successful decision, and it MUST NOT be
implemented by wrapping delegation in a rescue.

**Rationale:** A rendering plugin that hides its own failures produces mysteriously
mis-rendered pages instead of a stack trace, and the cause surfaces weeks later in user
complaints rather than immediately in a test run.

### IV. Detection Is Explainable, Versioned, and Overridable

The detector MUST satisfy all of:

- **Explainable.** It reports the winning format together with both scores, on demand, for
  operational investigation. Ambiguity is resolved by context rules over scoring patterns,
  not by adding more patterns.
- **Thresholded.** When the score difference falls below the configured threshold, it
  returns the configured default format rather than guessing.
- **Versioned.** `Detector` carries a version constant, and that constant is part of the
  formatted-HTML cache key. Changing scoring without bumping it is a defect.
- **Overridable.** An explicit `<!-- render_switcher: textile -->` directive wins over
  scoring, unconditionally and as the first rule evaluated.
- **Non-destructive.** Detection never mutates stored content. Round-tripping a text
  through `get_section` and `update_section` MUST return the body byte-identical apart from
  the edited section, directive line included.

**Rationale:** Detection costs ~0.29 ms against 14–48 ms of rendering, so accuracy and
debuggability matter and micro-optimization does not. Every item above corresponds to a
failure the feasibility report already reproduced.

### V. Quality Gates Are Part of "Done"

Work is not finished until, for the files it touched:

- `rubocop --ignore-parent-exclusion` reports zero offenses (run from the plugin directory).
- `bundle exec yard stats --list-undoc` reports 100% documentation coverage.
- The C0 coverage floor in Principle II holds.
- All user-facing strings resolve through `config/locales/en.yml` and `config/locales/ja.yml`
  via `t()` / `l()` — never hardcoded.
- Ruby files begin with `# frozen_string_literal: true` and use double-quoted strings.
- Comments, `docs/` content, and commit messages are in English.
- Logging goes through the plugin's own logger module. `Rails.logger` MUST NOT be called
  directly.
- HTML is built in ERB templates only. JavaScript is vanilla ES6 and MUST NOT construct
  HTML.

**Rationale:** No hook enforces these — `lefthook.yml` is still commented-out examples — so
they are enforced by the author on every change, or they are not enforced at all.

### VI. Simplicity: KISS, DRY, YAGNI

Three rules, in priority order when they conflict:

- **YAGNI.** Build only what a current requirement demands. Configuration options,
  abstraction layers, extension points, and "we might need this later" parameters MUST NOT
  be added speculatively. A feature with no caller is deleted, not kept.
- **KISS.** Prefer the plainest construction that works. A longer, obvious method beats a
  shorter, clever one. Metaprogramming, dynamic dispatch, and callback indirection require
  a stated reason that a direct implementation cannot satisfy.
- **DRY.** Knowledge is expressed once. Detection rules, format names, directive syntax,
  and setting keys have exactly one definition each. Duplication that is coincidental —
  two things that merely look alike today — is left alone; DRY applies to shared knowledge,
  not to similar-looking text.

When KISS and DRY conflict, the simpler code wins and the duplication is documented.

**Rationale:** The whole justification for Approach B is a small maintained surface. A
plugin that patches core classes cannot also afford internal complexity — the two compound,
and the Redmine upgrade that eventually breaks something must be debuggable.

## Redmine Integration Constraints

These are verified properties of the target environment, not preferences. Violating one
produces a defect that testing in isolation will not reveal.

- **Target:** Redmine 7.0.1-stable, Ruby 4.0, plugin mounted at
  `$REDMINE_ROOT/plugins/redmine_render_switcher`. All rake and rails commands run from
  `$REDMINE_ROOT`. `DB=sqlite3` is the default; MySQL and PostgreSQL are selectable and
  changes MUST NOT assume a single adapter.
- **Patch in `init.rb`, never inside `to_prepare`.** Plugin `init.rb` is itself re-executed
  inside `to_prepare`, so a nested block never fires.
- **Guard double-`prepend` by module name**
  (`klass.ancestors.any? {|m| m.name == "..." }`). Reloading makes the constant a different
  object, so `ancestors.include?(Mod)` silently fails.
- **A re-entrancy guard is mandatory.** Both formatters are patched, so the delegate is
  patched too and will recurse without one.
- **Never register the directive as a Redmine macro.** `textilizable` runs `catch_macros`
  before rendering and rewrites anything `macro_exists?` recognises into `{{macro(0)}}`,
  destroying the string the detector must read. The HTML-comment form is the supported
  spelling; both sanitizers drop it from output, so no stripping code is needed.
- **If a directive line is ever stripped, keep two delegate instances** — one from stripped
  text for `to_html`, one from raw text for `get_section` / `update_section` — or
  `update_section` deletes the directive on every save.
- **One text renders with one formatter.** Mixed-format content within a single body cannot
  be rendered correctly and MUST NOT be presented as supported.
- **Approach B also intercepts extension-driven rendering** (repository browsing of
  `.textile`/`.md`, attachment preview). This is accepted; only files whose extension already
  contradicts their content change behaviour.
- **A plugin setting MUST be able to disable auto-detection entirely**, restoring stock
  Redmine rendering.

## Development Workflow

### Branching

The branch strategy is **git-flow**, with exactly these branch types:

| Branch | Role |
|---|---|
| `main` | Production. Released code only. |
| `develop` | Integration branch. Feature work merges here. |
| `feature/NNN-description` | New functionality. Branches from and merges to `develop`. |
| `bugfix/NNN-description` | Defect fix on unreleased work. Branches from and merges to `develop`. |
| `release/X.Y.Z` | Release stabilisation. Branches from `develop`, merges to `main` and back to `develop`. |
| `hotfix/X.Y.Z` | Urgent production fix. Branches from `main`, merges to `main` and back to `develop`. |

Work MUST NOT be committed directly to `main` or `develop`.

- **Never commit or push without explicit user permission.**
- **Never run destructive git commands without an explicit instruction** — `git clean`,
  `git reset --hard`, `git checkout .` / `git restore .`, `git stash drop|clear`,
  `git branch -D`, `git rebase`, force pushes. To undo changes, revert only the specific
  files touched, named explicitly; never sweep the whole tree. Inspect first (for example
  `git clean -nd`) and confirm before removing anything.

### Documentation

- **`docs/` is consulted before work that it covers.** Filenames are the index: read the
  listing of `docs/`, judge relevance from the filename, and open what applies. There is no
  obligation to read everything — there is an obligation not to re-derive what `docs/`
  already answers.
- **New documents get self-describing filenames.** A reader MUST be able to decide from the
  filename alone whether the file is relevant. Names like `notes.md`, `memo.md`, or
  `design2.md` are rejected; `detector-scoring-rules.md` is the standard.
- **`docs/feasibility.md` is the authoritative design input** and is read before
  implementing anything it covers. It predates the English-only rule and stays in Japanese;
  new `docs/` content is written in English.

### Architecture Decision Records

- **Every significant design decision gets an ADR**, stored under `docs/adr/`. Significant
  means: it constrains future work, it was chosen over a named alternative, or reversing it
  later would be expensive. Choosing Approach B is the canonical example.
- **When unsure whether a decision warrants an ADR, ask the user.** The default on doubt is
  to ask, not to skip and not to write one unilaterally.
- **ADRs are append-only.** A past ADR's content is never modified or deleted. A decision
  that no longer holds is superseded by a new ADR that references it; the old one stays as
  written.
- **`docs/adr/README.md` indexes every ADR.** Adding an ADR includes adding its entry there
  in the same change. Adding the index entry is part of writing the ADR, not a follow-up.

### Verification

- **Feature work flows through Spec Kit.** `specs/<feature>/` holds `spec.md`, `plan.md`,
  and `tasks.md`, produced by the `speckit-*` skills.
- **Behaviour is probed, not assumed.** `bundle exec rails runner` against the real Redmine
  checkout is the way claims about core behaviour are settled, and the result is quoted in
  the spec, ADR, or commit that relies on it.

## Governance

This constitution supersedes conflicting practice. Where it and `CLAUDE.md` disagree, this
document governs and `CLAUDE.md` is corrected to match; where it is silent, `CLAUDE.md`
provides runtime development guidance.

**Amendment procedure.** Amendments are proposed as a change to this file, state which
principle or section is affected and why, and are approved by the project maintainer before
merge. A principle MUST NOT be weakened silently as a side effect of a feature branch: an
amendment is its own change.

**Versioning policy.** Semantic versioning applies to this document.

- MAJOR: a principle is removed or redefined in a backward-incompatible way.
- MINOR: a principle or section is added, or its guidance is materially expanded.
- PATCH: clarification, wording, or typo fixes that do not change meaning.

**Compliance review.** Every change verifies its own compliance before being called
complete: Principle V's gates are run, and any deviation from Principles I–IV or VI is
either fixed or recorded as an ADR with explicit justification. Complexity that is not
justified in writing is removed rather than merged. The three NON-NEGOTIABLE principles
admit no exception without a MAJOR amendment.

**Version**: 1.1.0 | **Ratified**: 2026-09-19 | **Last Amended**: 2026-09-19
