---
title: Section-edit numbering must agree with the rendered format
type: concept
sources: [S001, S002]
updated: 2026-09-19
---

# Section-edit numbering must agree with the rendered format

## Two numbering paths in Redmine

- The section-edit link's `section` parameter is numbered by counting `<h\d>`
  tags in the *rendered HTML* with `HEADING_RE`
  (`app/helpers/application_helper.rb:1384-1404`, `parse_sections`). (S001)
- `get_section` / `update_section` number sections through the Formatter's
  `extract_sections`. (S001)

If the two ran with different formats for the same text, the edit link would
open (and overwrite) the wrong section. (S001)

## Rule

`to_html` and `extract_sections` must use the same detection result and the same
delegate. Detection runs once per formatter instance and both the result and the
delegate are memoized. (S001, S002)

Rejected: re-detecting on every call. It would cost five times as much, and a
threshold setting changed mid-call could make the paths disagree. (S001)

## Known deviation

The Textile blank-line rule after a directive (see
[the directive page](./directive-html-comment-form.md)) shifts section numbers
by one. It is stock behaviour, documented and pinned by a test rather than
corrected. (S001, S002)

## See also

[Overview](./auto-format-detection-overview.md) ·
[AutoSwitch](./auto-switch-module.md)
