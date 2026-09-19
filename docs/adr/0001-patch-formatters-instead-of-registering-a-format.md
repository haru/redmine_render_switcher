# ADR-0001: Patch both formatters instead of registering a new format

- **Status**: Accepted
- **Date**: 2026-09-19

## Context

The plugin has to render a text with the formatter that matches how the text is
actually written, while a Redmine site keeps a single site-wide
`Setting.text_formatting`. Redmine offers an official extension point for this
shape of problem — `wiki_format_provider`, which registers an additional format
name — so the obvious reading of "add a format that auto-detects" is to use it.

Both routes were built and measured against a real Redmine 7.0.1 checkout; the
measurements are in `docs/feasibility.md` (sections 3, 6 and 10) and were taken with
`bin/rails runner` against the running application, not inferred from reading code.

Registering an `auto` format works for rendering, and section editing works too. The
cost is elsewhere: `Setting.text_formatting` then holds a value Redmine itself does
not understand, and the name leaks into roughly eight unrelated places, each of
which needs its own patch and its own re-verification on every Redmine upgrade —
the syntax help templates (`GET /help/wiki_syntax` returns 500 without one), the
`data-text-formatting` attribute on the edit form, the jstoolbar, the drag-and-drop
JavaScript, the Stimulus parameters for list auto-continuation and table paste, and
two places in `mail_handler`.

Principle I of the constitution requires an ADR for any change that widens the
coupling surface to Redmine core, which both options do.

## Decision

Prepend one module, `RedmineRenderSwitcher::AutoSwitch`, to both
`Redmine::WikiFormatting::Textile::Formatter` and
`Redmine::WikiFormatting::CommonMark::Formatter`. Detect the format inside that
module and delegate to the other formatter when the content disagrees with the site
setting. `Setting.text_formatting` keeps its ordinary value, `textile` or
`common_mark`, and Redmine never learns that anything changed.

`AutoSwitch` defines exactly the five methods of the formatter contract —
`initialize(text, options = {})`, `to_html`, `extract_sections`, `get_section`,
`update_section` — and touches no formatter internals. In particular it does not
read or write `@filter`, which `Textile::Formatter` uses to implement
`extract_sections` through `Forwardable`.

## Alternatives considered

**Register an `auto` format through `wiki_format_provider`.** Rejected. It is the
official API and it stays inside supported extension points, but it makes the
number of places the plugin has to patch grow with Redmine's own use of the format
name. Every one of those eight sites is a place a future Redmine release can break
independently, and each break shows up as a broken page rather than a failing test.

**Patch `ApplicationHelper#textilizable` or `Redmine::WikiFormatting.to_html`.** Not
pursued. It moves the interception one level up without narrowing anything: section
editing still reaches the formatter directly, so the formatter would need patching
as well, leaving two coupling points instead of one.

## Consequences

The plugin's entire exposure to a Redmine upgrade is the formatter contract. What
must be re-verified after upgrading Redmine is exactly those five method signatures
and the assumption that both formatter classes still exist under the same names;
`test/unit/lib/redmine_render_switcher/auto_switch_test.rb` fails loudly if any of
it changes.

Nothing on the write side changes: the toolbar, the syntax help, image paste, list
auto-continuation and quoted replies all keep working off the site setting, with no
plugin code involved. That is a deliberate asymmetry — reading is detected, writing
is not — and it is what makes an incremental Textile-to-Markdown migration possible
without telling users anything.

Because the patch sits in the formatter rather than in a format name, it also
intercepts rendering driven by a file extension: browsing a `.textile` or `.md` file
in a repository, and attachment previews. Only files whose extension already
contradicts their content are affected, which is a small and arguably correct
change, but it is a behaviour the official-API route would not have had.

Two guards are structural rather than incidental, and removing either one breaks the
plugin in a way that is hard to diagnose. The module must be prepended directly from
`init.rb`, never inside `Rails.application.config.to_prepare`, because the plugin
loader already re-runs `init.rb` inside `to_prepare` and a nested one never fires.
And double application must be prevented by comparing module *names*, because
reloading rebuilds the constant as a different object, so `ancestors.include?(Mod)`
does not see the copy that is already installed.

A re-entrancy guard is required for the same reason the design works at all: the
formatter being delegated to carries the same module.
