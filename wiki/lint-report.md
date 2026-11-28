# Wiki Lint Report — 2026-11-28

| # | Check | Severity | Page | Finding | Suggested fix |
|---|-------|----------|------|---------|---------------|
| 1 | contradictions | semantic | detector-textile-insertion.md:34 | Unresolved marker: S005 opening boundary `(?<![^\s(*\|])` vs the stricter shipped lookbehind and ADR-0006. Code wins. | Keep until S005 is superseded, or delete once accepted. |
| 2 | stale | semantic | cache-key-detector-version.md, detector-design.md, detector-line-patterns.md, detector-textile-image.md | These pages cite S009 (and S010 for the first two) and are dated 2026-11-27; both sources were re-ingested on 2026-11-28 with unchanged content. `detector-textile-image.md` was also edited on 2026-11-28 (split) without a date bump. | None needed; touch `updated` on the next real edit. Low value. |

No findings for `index-drift`, `links`, `orphans` or `citations`. All 21 pages are in `INDEX.md` and linked from another page, every page is within the 600-word cap, and all cited S-ids (S001-S011) exist in `sources.md`. Every page cited in `sources.md` exists. No page is over 90 days old.
