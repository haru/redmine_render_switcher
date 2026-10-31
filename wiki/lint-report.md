# Wiki Lint Report — 2026-10-31

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | detector-design.md:18 | Unresolved marker: S001/S002 (one context rule, fences and `<pre>` only) vs S003/S004 (four rules, indented blocks masked). Page text already says the later design applies. | Delete the marker; the resolution is stated in the page. |
| 2 | contradictions | semantic | detector-design.md:51 | Unresolved marker: S001 lists `**bold**` as decisive Markdown and `\|table\|` as unscored; S003 reverses both. Later decision applies. | Delete the marker. |
| 3 | contradictions | semantic | detector-line-patterns.md:44 | Unresolved marker: S003 gives `LIST_ITEM_LINE` with `#+`; code and CLAUDE.md omit it. Code wins. | Delete the marker, or fix the S003 row to match the code. |
| 4 | contradictions | semantic | detector-score-once-per-block.md:47 | Unresolved marker about the S003 list-block definition. | Read the marker; keep or drop it once the page states the winning definition. |
| 5 | contradictions | semantic | detector-textile-insertion.md:34 | New marker: S005 regex opening boundary `(?<![^\s(*\|])` vs the shipped lookbehind in `detector.rb` and ADR-0006. Code wins. | Keep until S005 is superseded, or delete once you accept the note. |

No findings for `index-drift`, `links`, `orphans` or `citations`. All cited S-ids (S001-S006) exist in `sources.md`, and every page is in `INDEX.md` and linked from another page. No page is older than 90 days; the oldest is 2026-09-19. The bullet-line hits in `detector-textile-insertion.md` for `citations` are false positives, since the citation sits on a continuation line.
