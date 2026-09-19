# ADR-0003: Forward the formatter constructor's arguments untouched

- **Status**: Accepted
- **Date**: 2026-09-19

## Context

ADR-0001 confined the plugin to the five-method formatter contract and wrote the
constructor of that contract as `initialize(text, options = {})`. That signature was
measured against a Redmine 7.0.1 checkout only, while the plugin declares
`requires_redmine version_or_higher: "6.0.0"` and CI builds against 6.0-stable,
6.1-stable, 7.0-stable and master.

The constructor is not the same in every one of those releases. Read from the
`lib/redmine/wiki_formatting*` sources of each branch of `redmine/redmine`:

| Redmine | `CommonMark::Formatter#initialize` | `Textile::Formatter#initialize` | `WikiFormatting.to_html` builds it with |
|---|---|---|---|
| 6.0-stable | `(text)` | `(*args)` | `.new(text)` |
| 6.1-stable | `(text)` | `(*args)` | `.new(text)` |
| 7.0-stable | `(text, options = {})` | `(text, options = {})` | `.new(text, options)` |
| master | `(text, options = {})` | `(text, options = {})` | `.new(text, options)` |

`AutoSwitch#initialize(text, options = {})` ended in a bare `super`, which forwards
both arguments. On 6.0 and 6.1 that call reaches `CommonMark::Formatter#initialize`
with two arguments where it takes one. The failure is therefore not limited to the
delegating path: every CommonMark construction raised, so any Redmine 6.0 or 6.1 site
whose format is `common_mark` would have broken on installing the plugin. CI showed it
as

```
ArgumentError: wrong number of arguments (given 2, expected 1)
    lib/redmine/wiki_formatting/common_mark/formatter.rb:67:in `initialize'
    plugins/redmine_render_switcher/lib/redmine_render_switcher/auto_switch.rb:65:in `initialize'
```

on every 6.0-stable and 6.1-stable job, and on none of the 7.0-stable or master jobs.

The 6.0 and 6.1 signatures above come from reading those branches' sources and from
the CI failure, not from running `bin/rails runner` against a 6.0 or 6.1 checkout;
the development checkout is 7.0.1.

## Decision

`AutoSwitch#initialize` takes `(text, *options)`, keeps the extra arguments as an
array, and forwards them unchanged to both places that construct a formatter:

- `super`, which is the site setting's own formatter, and
- the delegate, built as `formatter_for(format).new(text, *options)`.

The plugin therefore never decides how many arguments a formatter takes. It passes on
what the running core passed. Giving the delegate the same arguments as the formatter
being wrapped is sound because both formatters are built by the same core call site
within any one release, so they share a constructor shape.

The constructor line in ADR-0001's description of the contract is to be read as
"`initialize(text, *options)`, where `options` is whatever the running Redmine
passes". ADR-0001 is otherwise unchanged and remains in force.

## Alternatives considered

**Keep `options = {}` and raise the minimum to Redmine 7.0.** Rejected. The README,
`init.rb` and the CI matrix all promise 6.0, and Redmine 6.0 and 6.1 are exactly the
releases a long-time Textile site is most likely to still run. Dropping them to
avoid one argument is out of proportion.

**Branch on `Redmine::VERSION` or on the constructor's `arity`.** Rejected. It puts a
second copy of Redmine's calling convention into the plugin, to be kept in step by
hand, and it needs a new branch for every release that changes the shape again.
Forwarding needs no knowledge of the shape at all.

**Drop the stored options and build the delegate from the text alone.** Rejected. On
7.0 the options are real input to the formatter, so discarding them would make the
delegate render differently from the formatter it stands in for.

## Consequences

The constructor arguments no longer need re-verifying per release, which is the point;
nothing else about the contract changes, and the other four methods were never
affected.

The bug cannot be reproduced with Redmine's real classes on 7.0 or master, because
their constructors accept both shapes. `auto_switch_test.rb` therefore covers it with
stand-in classes that take exactly one argument and exactly two, prepended with
`AutoSwitch`. A regression back to a fixed two-argument `super` fails there on any
Redmine version; the CI matrix on 6.0-stable and 6.1-stable remains the check against
the real classes.

Other differences between 6.0, 6.1 and 7.0 exist that the plugin does not depend on
but its tests once did: the `data-list-autofill-*` attributes on wiki textareas
appear from 6.1 and `data-table-paste-*` from 7.0, so the functional tests that
assert them are skipped on the older releases.
