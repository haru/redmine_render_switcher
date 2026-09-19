# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this plugin is

`redmine_render_switcher` auto-detects whether a Redmine text field (issue description, journal, wiki page, news …) is written in **Textile** or **Markdown** and renders it with the matching formatter, so a site that has historical Textile content can let users write new content in Markdown without converting anything. Target user: a long-time Textile Redmine installation that wants to move to Markdown incrementally.

**Current state: the repository is still the unmodified `redmine_plugin_boilerplate` skeleton** (`init.rb` has placeholder metadata, `app/`, `lib/`, `db/migrate/` are empty, `test/` has only `test_helper.rb`). The design work lives in `docs/feasibility.md`; there is no implementation yet.

## Read `docs/feasibility.md` before implementing anything

`docs/feasibility.md` (Japanese, 528 lines) is a verified feasibility report written against the actual Redmine 7.0.1 checkout — every claim in it was confirmed with `bin/rails runner`. It is the authoritative design document. Its conclusions constrain the implementation:

- **Approach B is the chosen design**: `prepend` a module to `Redmine::WikiFormatting::Textile::Formatter` and `Redmine::WikiFormatting::CommonMark::Formatter`, detect the format inside, and delegate to the *other* formatter when the content disagrees with `Setting.text_formatting`. `Setting.text_formatting` keeps its normal value (`textile` / `common_mark`).
- Approach A (registering a new `auto` format via the official `wiki_format_provider` API) was rejected: the format name leaks into ~8 unrelated places (help templates, jstoolbar, drag-and-drop JS, Stimulus params, `mail_handler`), each of which then needs its own patch and re-checking on every Redmine upgrade. Approach B reduces the surface Redmine can break to one thing: the Formatter contract (`initialize(text, options = {})`, `to_html`, `extract_sections`, `get_section`, `update_section`).
- Planned layout: `lib/redmine_render_switcher/detector.rb` (scoring detector, carries a version constant for cache keys), `auto_switch.rb` (the prepended module), `directive.rb` (explicit format override).

### Pitfalls the report already proved out — do not rediscover them

- **Do not wrap the `prepend` in `Rails.application.config.to_prepare`.** Plugin `init.rb` is itself re-executed inside `to_prepare` (`lib/redmine/plugin_loader.rb`), so a nested `to_prepare` never fires. Patch directly in `init.rb` and guard against double-prepend by module **name** (`klass.ancestors.any? {|m| m.name == "..." }`) — reloading makes the constant a different object, so `ancestors.include?(Mod)` does not work.
- **A re-entrancy guard is required** (e.g. a `Thread.current` flag) because the delegate formatter is also patched.
- **Never register the `{{render_switcher_*}}` directive as a Redmine macro.** `textilizable` runs `catch_macros` *before* rendering and replaces any macro that `macro_exists?` recognises with `{{macro(0)}}` — registering it destroys the very string the detector needs to read. Prefer the `<!-- render_switcher: textile -->` HTML-comment form: both sanitizers drop it from the output, so no stripping code is needed and the section-edit bug below cannot occur.
- **If you do strip a directive line, keep two delegate instances**: one built from the stripped text for `to_html`, one from the raw text for `get_section` / `update_section`. Otherwise `update_section` rebuilds the body from the stripped text and silently deletes the directive line on every save.
- **Detector design**: naive pattern scoring mis-reads Textile's numbered-list `# item` as a Markdown `h1`. Resolve with context rules, not more patterns. Detection cost is ~0.29 ms against 14–48 ms of rendering, so accuracy matters far more than speed.
- Approach B also intercepts extension-driven rendering (repository browsing of `.textile`/`.md`, attachment preview). Only files whose extension already contradicts their content are affected.
- Still required under Approach B: add the detector version to the HTML cache key, and a plugin setting to disable auto-detection.

## Environment

Devcontainer-based. The plugin is mounted **inside** a full Redmine checkout at `/usr/local/redmine/plugins/redmine_render_switcher`; `$REDMINE_ROOT` is `/usr/local/redmine`. Redmine 7.0.1-stable, Ruby 4.0. Reading Redmine core source (`app/helpers/application_helper.rb`, `lib/redmine/wiki_formatting*`) is the normal way to answer questions here.

`DB=sqlite3` by default; `.devcontainer/post-create.sh` also prepares MySQL and PostgreSQL databases, selectable by exporting `DB`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT` (see that script for the value sets).

## Commands

All rake/rails commands run from `$REDMINE_ROOT`, not from the plugin directory.

```bash
# All plugin tests (unit + functional + integration + system)
cd /usr/local/redmine && bundle exec rake redmine:plugins:test NAME=redmine_render_switcher

# One category (these depend on db:test:prepare, the bare :test task does not)
bundle exec rake redmine:plugins:test:units NAME=redmine_render_switcher

# A single test file, or a single test by name
bundle exec ruby -Itest plugins/redmine_render_switcher/test/unit/detector_test.rb
bundle exec ruby -Itest plugins/redmine_render_switcher/test/unit/detector_test.rb -n test_detects_textile_heading

# Lint (config lives in the plugin; run it from the plugin directory).
# Currently broken by a missing gem — see "Linting & Quality" below.
cd /usr/local/redmine/plugins/redmine_render_switcher
rubocop --ignore-parent-exclusion
rubocop --ignore-parent-exclusion -a

# YARD doc coverage (must stay at 100%)
yard stats --list-undoc

# Plugin migrations / dev server
cd /usr/local/redmine
bundle exec rake redmine:plugins:migrate
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rails s -b 0.0.0.0        # port 3000 is forwarded

# Fastest way to probe Redmine behaviour (how docs/feasibility.md was produced)
bundle exec rails runner 'puts Redmine::WikiFormatting.formats.inspect'
```

Tests are Redmine's Rails/minitest setup: `test/test_helper.rb` requires `../../../test/test_helper`, so `ActiveSupport::TestCase`, Redmine fixtures and `ActionController::TestCase` are all available.

## Coding Conventions

### Ruby
- Follow Ruby on Rails conventions
- `# frozen_string_literal: true` at file top
- Double quotes for string literals (enforced by RuboCop)
- Write comments in English
- Logging: mix in the plugin's own logger module and use its helper method — **never** `Rails.logger`.
  (The rule as handed over names `RedmineAiHelper::Logger` / `ai_helper_logger`, which belongs to the
  separate `redmine_ai_helper` plugin. This plugin has no logger module yet — port one under
  `lib/redmine_render_switcher/` before this rule can be followed literally.)
- Error handling: **NEVER implement fallback error handling**. Let errors surface immediately. No silent continues.
  (Note the tension with the Formatter patch: `AutoSwitch` must return `super` — the setting's own
  formatter — when detection is inconclusive. That is the designed behaviour, not a swallowed error;
  do not wrap the delegation in a rescue.)

### Testing
- **TDD**: Write tests before implementing features
- Framework: `shoulda` (context/should blocks) + `mocha` (mocking external servers only)
- Test fixtures: `test/model_factory.rb` (FactoryBot)
- Test structure: `test/unit/` (models, agents, tools), `test/unit/lib/` (lib classes), `test/functional/` (controllers), `test/integration/` (API)
- Not yet set up here: only `mocha` is available (it is in Redmine's `Gemfile`); `shoulda-context` and
  `factory_bot` are not installed, and `test/model_factory.rb` does not exist. Add the gems in a plugin
  `Gemfile` at the plugin root — Redmine's `Gemfile:133` eval-loads `plugins/*/{Gemfile,PluginGemfile}` —
  then `bundle install` from `$REDMINE_ROOT`.
- The detector is the natural TDD centre: table-driven unit tests over the Textile/Markdown samples in
  `docs/feasibility.md`, which are written to be reusable as the initial case set.

### Frontend
- HTML in ERB templates only — **never build HTML in JavaScript** (XSS prevention)
- JavaScript: vanilla ES6 only (`const`/`let`, classes), no jQuery
- Write comments in English
- CSS: use Redmine's existing classes (`.box`), no custom colors/fonts
- Icons: `sprite_icon` helper; i18n: `t()` / `l()`

## Git Workflow
- **git-flow**: `develop` is integration branch, `main` is production — always branch from `develop`
- Branch naming: `feature/NNN-description`, `bugfix/NNN-description`
- Write commit messages in plain English
- Do not include any information about Claude Code in commit messages
- **NEVER commit or push without explicit user permission**
- **NEVER run destructive git commands without an explicit user instruction** — this includes
  `git clean`, `git reset --hard`, `git checkout .` / `git restore .`, `git stash drop|clear`,
  `git branch -D`, `git rebase`, and force pushes. They discard work that git cannot recover,
  including untracked files that are not in any commit.
- To undo your own changes, delete or revert **only the specific files you touched**, named
  explicitly. Never use a whole-tree sweep to "tidy up" — the working tree may hold untracked
  files (local tooling directories, caches, scratch work) that belong to the user, not to you.
- Before removing anything, inspect what will be removed (e.g. `git clean -nd`) and confirm with
  the user.

## Documentation & ADRs
- Technical docs in `docs/`; ADRs in `docs/adr/`
- All docs/ content in English
- ADRs are **append-only** — add new ones to supersede; never modify or delete past ADRs
- Format: use template in `docs/adr/README.md`
- Not yet set up here: `docs/adr/` and its `README.md` template do not exist. `docs/feasibility.md`
  predates this rule and is written in Japanese — leave it as is; write new `docs/` content in English.
  The Textile-vs-Markdown approach decision (Approach B) is the obvious first ADR.

## Internationalization
- All user-facing text via `config/locales/*.yml` using `t()` helper
- Support English (en) and Japanese (ja)
- `config/locales/en.yml` exists but is still the empty boilerplate stub; `ja.yml` does not exist yet.

## Linting & Quality
- **Rubocop**: after modifying any Ruby source file, always run `rubocop --ignore-parent-exclusion` and
  fix all offenses before finishing; config in `.rubocop.yml`. Use the `/rubocop` skill for the full fix
  workflow including auto-correction and test verification. (That skill is not installed in this
  environment — the available skills are the `speckit-*` set. Run the command manually until it is added.)
- **Blocker**: `rubocop` currently aborts with `cannot load such file -- rubocop-factory_bot`, because
  `.rubocop.yml` lists that plugin under `plugins:` and the gem is not installed. Install it or remove
  that line; with it removed, rubocop runs clean on the current tree.
- `.rubocop.yml` disables most of `Layout`, `Naming`, `Style` and `Performance` but enables `Lint`,
  `Metrics`, `Rails` and `Security`. Style points that do bite: double-quoted strings, spaces inside
  array/hash literal brackets (`[ a, b ]`, `{ a: 1 }`), `%w[]`/`%r{}`/`%i[]` delimiters, trailing commas
  in multiline literals. Several `Exclude:` lists still point at `lib/redmine_ai_helper/**` paths
  inherited from another project.
- **YARD**: doc coverage (must be 100%) — `yard` is available via Redmine's `Gemfile`; check with
  `bundle exec yard stats --list-undoc` from the plugin directory.
- **lefthook** is installed (`lefthook install` runs in post-create) but `lefthook.yml` is still entirely
  commented-out examples — no hooks actually run, so the rubocop rule above is on you, not on a hook.
- The boilerplate `README.md` / `README.rdoc` / `README_ja.md` are deleted in the working tree and need
  replacing with plugin-specific content.

## spec-kit workflow

This repo is initialized with spec-kit (`.specify/`), exposed as the `speckit-*` skills (`speckit-specify`, `speckit-plan`, `speckit-tasks`, `speckit-implement`, `speckit-analyze`, `speckit-clarify`, `speckit-converge`, `speckit-checklist`, `speckit-constitution`). Feature artifacts (`spec.md`, `plan.md`, `tasks.md`) go under `specs/<feature>/`; scripts in `.specify/scripts/bash/` resolve the active feature directory from `.specify/feature.json` or `$SPECIFY_FEATURE_DIRECTORY`. `.specify/memory/constitution.md` is still the unfilled template — run `speckit-constitution` before relying on it.
