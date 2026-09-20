---
title: Detector scan structure — four scans plus one masking machine
type: decision
sources: [S003, S004]
updated: 2026-09-20
---

# Detector scan structure — four scans plus one masking machine

## Decision

The context rules are four independent line scans, `score_hash_lines` (existing),
`score_list_blocks`, `score_table_blocks` and `score_setext_headings`;
`context_scores` sums their `[textile, markdown]` pairs. Only indented-block
masking is folded into the existing `mask_code_blocks` state machine. (S003, S004)

## Why

- The table rule has the same shape as the `#` rule (walk lines, count a run,
  score at its end), so parallel functions read alike. One combined scan would
  carry six or more state variables and pass Metrics without being readable
  (Constitution VI, KISS). (S003)
- Masking must be single-pass: an indented block opens only after a blank line
  and only when the last non-blank line is not a list item, the same state
  fences and `<pre>` use. (S003)

## Rejected

- **One scan for everything**: unreadable state. (S003)
- **Two masking passes (fences, then indents)**: masked lines become blank, so
  the second pass's "previous line was blank" test is polluted by the first. (S003)

## Traps

- Update `prev_blank` and `prev_list` from the **original** line, not the masked
  one, or an indent right after a fence opens a false block. (S004)
- If `mask_code_blocks` exceeds RuboCop Metrics, extract
  `indented_block_start?(line, prev_blank, prev_list)`; not before. (S004)
- Known limit (FR-014): indentation at the very start of a text has no preceding
  blank line, so no block opens; the verdict is unchanged (Textile 4:0). (S003)

## Cost

204 lines / 4,884 bytes of Textile: old detector 0.180 ms, new 0.315 ms
(about 1.75x), Textile render 9.309 ms, so 3.39% of render against the 5%
ceiling (SC-011). No single-pass optimisation (YAGNI). (S003, S004)

## Version

The revision moves the tables, masking and context rules, so
`Detector::VERSION` goes 3 to 4 in the same change; see
[cache key](./cache-key-detector-version.md). (S003)

## See also

[Detector design](./detector-design.md) ·
[Line patterns](./detector-line-patterns.md) ·
[Score once per block](./detector-score-once-per-block.md)
