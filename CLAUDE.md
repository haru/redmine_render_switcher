# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this plugin is

`redmine_render_switcher` auto-detects whether a Redmine text (issue description, journal, wiki page, news …) is written in **Textile** or **Markdown** and renders it with the matching formatter, so a long-time Textile site can let users write new content in Markdown without converting anything. Only rendering changes; stored text is never modified and the plugin adds no tables or migrations.

**Current state: implemented (v0.0.1) on `feature/001-auto-format-detection`.** The full suite passes (99 runs), RuboCop is clean, YARD is at 100% and C0 coverage of `lib/` is 100%. New work is changes to a working plugin, not a greenfield build.

## Architecture

The whole plugin is ~640 lines (mostly YARD comments) in `lib/redmine_render_switcher/`, wired up from `init.rb`. It couples to Redmine core at exactly **two points** (ADR-0001, ADR-0002, ADR-0004):

1. **`AutoSwitch`** is prepended to both `Redmine::WikiFormatting::Textile::Formatter` and `…::CommonMark::Formatter`. It overrides only the five-method formatter contract (`initialize(text, *options)`, `to_html`, `extract_sections`, `get_section`, `update_section`; Redmine 6.0/6.1 construct formatters with the text alone and 7.0+ adds an options hash, so the extra constructor arguments are forwarded untouched — ADR-0003), never formatter internals such as `@filter`. If the detected format differs from the formatter's own, it builds the *other* formatter via `Redmine::WikiFormatting.formatter_for` and delegates. When detection is inconclusive it returns `super` — the site setting's formatter. `Setting.text_formatting` keeps its normal value (`textile` / `common_mark`); no new format is registered.
2. **`CacheKey`** is prepended to `Redmine::WikiFormatting.singleton_class` and appends `-rs<Detector::VERSION>t<threshold>` to `cache_key_for`. This is needed because the cache lookup happens *before* any formatter exists. It passes `nil` through, and adds nothing when auto-detect is off (disabled must be byte-identical to not installed).

Everything else feeds those two: `Detector` (scoring; returns a `Result` carrying both scores and a `reason`), `Directive` (first-line override), `PluginSettings` (the only place setting keys and their string normalisation live), `Logger` (debug-only, block form).

Decision order inside `AutoSwitch`: setting off → re-entrancy flag set → not one of the two known formatters → **directive** (evaluated before, and instead of, scoring) → `Detector.detect` → format nil or equal to own → otherwise delegate.

### Invariants that are easy to break

- **Bump `Detector::VERSION`** in the same change as anything that can move a verdict: the pattern tables, the `#` line-context rule, code-block masking, the threshold comparison, or `Directive::PATTERN`. Forgetting is a defect — stale cached HTML keeps being served. The threshold is a setting, so `CacheKey` handles it separately.
- **Detection and the delegate are memoized per formatter instance.** `to_html` numbers sections from rendered `<h\d>` tags while `get_section` numbers them from source; both must see the same verdict or a section edit overwrites the wrong section. Don't re-detect per call.
- **Do not wrap the `prepend` in `Rails.application.config.to_prepare`.** The plugin loader already re-runs `init.rb` inside `to_prepare`, so a nested one never fires. Patch directly in `init.rb`; both `prepend_to` helpers guard against double-prepend by module **name**, because reloading makes the constant a different object and `ancestors.include?(Mod)` fails.
- **The re-entrancy guard is required** (`Thread.current[REENTRANCY_KEY]`): the delegate formatter carries `AutoSwitch` too. The guard restores the previous value rather than clearing it.
- **Never register the directive as a Redmine macro.** `textilizable` runs `catch_macros` first and rewrites any recognised macro to `{{macro(0)}}`, destroying the string the detector reads. The directive is the HTML comment `<!-- render_switcher: textile|markdown -->` on line 1 only; both sanitizers drop it, so there is no stripping code — and there must not be, or `update_section` would delete the line on every save. (If stripping is ever added: two delegates, stripped text for `to_html`, raw text for `get_section`/`update_section`.)
- **Detector ambiguity is resolved with context rules, not more patterns.** Textile's `# item` numbered list collides with Markdown's `h1`; two or more `#` lines in a row score Textile, a lone one scores Markdown. Notation both formats read identically is deliberately unscored. The score margin is clamped to ≥ 1 so a tie never picks a side. `Result` never carries the text, so debug logs cannot leak page content.
- **Errors surface; there is no fallback handling.** `return super` on inconclusive detection is the designed outcome, not a swallowed error — never implement it with a `rescue`.
- Known, accepted quirk: in Textile a heading only counts after a blank line, so a directive on line 1 with no blank line after it shifts section numbers by one. Documented in `docs/directive-usage.md` and pinned by a test, not corrected.
- Approach B also intercepts extension-driven rendering (repository `.textile`/`.md` browsing, attachment preview). Accepted.

## Project documents — what to read

- **`docs/adr/`** — the design record (ADR-0001 patch formatters instead of registering a format; ADR-0002 detector version in the cache key, superseded by ADR-0004 which adds the score threshold; ADR-0003 forward the formatter constructor's arguments untouched). Append-only; index in `docs/adr/README.md`. Read before changing either coupling point.
- **`.specify/memory/constitution.md`** (v1.1.0) — six principles; it **governs where it disagrees with this file**. The three non-negotiable ones: minimal core surface (any new `prepend`/patched core class needs an ADR), test-first, errors surface immediately.
- **`docs/directive-usage.md`** — user-facing directive documentation.
- **`specs/001-auto-format-detection/`** — spec-kit `spec.md`, `plan.md`, `tasks.md`, `data-model.md`. Gitignored, and written in **Japanese** (`specs/CLAUDE.md`). `.specify/feature.json` points at the active feature.
- **`wiki/`** — an LLM-maintained summary of the above, maintained via the `speckit-wiki-*` skills. It is derived (and can drift: one page still contradicts the current RuboCop state); when it disagrees with code, ADRs or the constitution, those win.
- **`docs/feasibility.md` is not in the repository** (it was never committed), though the constitution and some wiki pages still call it the authoritative design input. Its conclusions and measurements survive in the ADRs. Don't go looking for it; if a claim about Redmine core behaviour is needed, probe it (below).

## Environment

Devcontainer-based. The plugin is mounted **inside** a full Redmine checkout at `/usr/local/redmine/plugins/redmine_render_switcher`; `$REDMINE_ROOT` is `/usr/local/redmine`. Redmine 7.0.1-stable, Ruby 4.0 (`init.rb` declares `requires_redmine version_or_higher: "6.0.0"`). Reading Redmine core (`app/helpers/application_helper.rb`, `lib/redmine/wiki_formatting*`) is the normal way to answer questions here, and `bin/rails runner` against the checkout is how core behaviour claims are settled — quote the result in the spec/ADR/commit that relies on it.

`DB=sqlite3` by default; `.devcontainer/post-create.sh` also prepares MySQL and PostgreSQL databases, selectable by exporting `DB`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`.

## Commands

Rake/rails commands run from `$REDMINE_ROOT`, not the plugin directory.

```bash
cd /usr/local/redmine

# All plugin tests
bundle exec rake redmine:plugins:test NAME=redmine_render_switcher

# One category (units = test/unit/**; depends on db:test:prepare, the bare :test task does not)
bundle exec rake redmine:plugins:test:units NAME=redmine_render_switcher

# One file, or tests matching a name/regex (shoulda names are the full "should ..." sentence)
bundle exec ruby -Itest plugins/redmine_render_switcher/test/unit/lib/redmine_render_switcher/detector_test.rb
bundle exec ruby -Itest plugins/redmine_render_switcher/test/unit/lib/redmine_render_switcher/detector_test.rb -n "/never name a winner/"

# C0 coverage over the plugin's lib/ only (constitution floor: 90%; currently 100%)
COVERAGE=1 bundle exec rake redmine:plugins:test NAME=redmine_render_switcher

# Lint and doc coverage — from the plugin directory; both must stay clean
cd /usr/local/redmine/plugins/redmine_render_switcher
rubocop --ignore-parent-exclusion          # add -a to auto-correct
bundle exec yard stats --list-undoc        # must report 100% documented

# Dev server (port 3000 is forwarded); the plugin has no migrations
cd /usr/local/redmine && bundle exec rails s -b 0.0.0.0

# Probe Redmine behaviour
bundle exec rails runner 'puts Redmine::WikiFormatting.formats.inspect'
```

## Testing

- **TDD** (constitution principle II): write the failing test first; every bug fix starts with a test that reproduces it. Mock only external servers — detector and formatter paths run for real.
- Tests are Redmine's minitest setup: `test/test_helper.rb` requires `../../../test/test_helper`, so Redmine fixtures, `ActionController::TestCase` and integration tests are all available. It also patches `Rails::TestUnitReporter#format_rerun_snippet` to work around a shoulda-context / Railties 8.1 incompatibility — leave that in place.
- Layout: `test/unit/lib/redmine_render_switcher/*_test.rb` (one per lib file; the detector test is table-driven over Textile/Markdown samples), `test/functional/` (end-to-end rendering), `test/integration/` (section edit round-trip: the body must come back byte-identical apart from the edited section, directive line included).
- Style: `shoulda` `context`/`should` blocks in `ActiveSupport::TestCase`. The plugin `Gemfile` also lists `factory_bot_rails` etc., but no factory file exists and nothing uses it.
- Coverage must come from tests that would fail if the line were wrong, not from executing code without asserting.

## Coding conventions

- **Everything that gets committed is written in English**: commit messages, source-code comments (including YARD docs), test fixtures and assertion strings, `README.md`, and every other committed document (`docs/`, ADRs, `wiki/`). The plugin is headed for OSS release and must be maintainable by contributors worldwide, so this holds even when the user is conversing in Japanese and even when surrounding text is Japanese. Exceptions, and only these: `config/locales/ja.yml` (the Japanese translation of user-facing strings), fixtures where non-ASCII text is itself what the test exercises (say so in a comment at the fixture), and the gitignored `specs/`, which is Japanese by its own `specs/CLAUDE.md`.
- Ruby on Rails conventions; `# frozen_string_literal: true`; double-quoted strings.
- **YARD-document everything** (coverage must stay 100%), including private methods, constants and `Data` attributes.
- **Logging**: mix in `RedmineRenderSwitcher::Logger` and call `render_switcher_logger.debug { "…" }` (block form, debug only, never the text itself). **Never `Rails.logger`.**
- **No fallback error handling.** No `rescue` that swallows, no silent defaults, no defensive `nil` guard hiding a broken assumption. Errors propagate.
- YAGNI / KISS / DRY (constitution VI): format names, setting keys, directive syntax and detection rules each have exactly one definition. Don't add options or abstractions speculatively.
- RuboCop (`.rubocop.yml`): `Lint`, `Metrics`, `Rails`, `Security` enabled; most of `Layout`/`Naming`/`Style` off. Style that bites: spaces inside array/hash brackets (`[ a, b ]`, `{ a: 1 }`), `%w[]`/`%r{}`/`%i[]`, trailing commas in multiline literals. Several `Exclude:` entries still name `lib/redmine_ai_helper/**` (inherited; harmless). Run RuboCop as plain `rubocop`, not through `bundle exec`, after touching any Ruby file.
- **Frontend**: HTML in ERB only, never built in JavaScript; vanilla ES6, no jQuery; Redmine's own CSS classes (`.box`), no custom colours/fonts; `sprite_icon` for icons. The only view is `app/views/settings/_redmine_render_switcher_settings.html.erb` — the partial name carries the plugin name because Redmine warns on collisions.
- **i18n**: every user-facing string goes through `config/locales/en.yml` and `ja.yml` via `t()`/`l()`.
- New design decisions that constrain future work, were chosen over a named alternative, or are costly to reverse get an ADR (`docs/adr/`, template in its README, add the index line in the same change). **If unsure whether one is warranted, ask — don't skip and don't write one unilaterally.** ADRs are never edited after the fact; supersede instead.

## Git workflow

- **git-flow**: `develop` is the integration branch, `main` is production; branch from `develop` as `feature/NNN-description` or `bugfix/NNN-description`. Never commit directly to `main`/`develop`.
- **NEVER commit or push without explicit user permission.**
- Commit messages: English (see Coding conventions), and no mention of Claude Code. (`lefthook.yml` has a `commit-msg` hook that strips `Co-Authored-By: …Claude…`, `Claude-Session:` and "Generated with Claude Code" lines anyway.)
- **NEVER run destructive git commands without an explicit instruction**: `git clean`, `git reset --hard`, `git checkout .` / `git restore .`, `git stash drop|clear`, `git branch -D`, `git rebase`, force pushes. To undo your own changes, revert **only the specific files you touched**, named explicitly — the tree may hold untracked files that belong to the user. Inspect first (`git clean -nd`) and confirm before removing anything.

## Spec Kit

Feature work flows through spec-kit, exposed as `speckit-*` skills (`specify`, `plan`, `tasks`, `implement`, `analyze`, `clarify`, `converge`, `checklist`, `constitution`, `review-*`, `wiki-*`). Scripts are in `.specify/scripts/bash/`; the active feature comes from `.specify/feature.json` or `$SPECIFY_FEATURE_DIRECTORY`. `AGENTS.md` just points other agents back at this file.
