# Architecture Decision Records

This directory records the decisions that shape `redmine_render_switcher`: the ones
that constrain future work, that were taken over a named alternative, or that would
be expensive to reverse.

## Rules

- **ADRs are append-only.** The content of an ADR is never edited or deleted once
  written. A decision that no longer holds is superseded by a new ADR that
  references the old one; the old one stays exactly as it was, including the parts
  that turned out to be wrong. Its value is the record of what was believed and why.
- **Adding an ADR includes adding its line to the index below**, in the same change.
  That is part of writing the ADR, not a follow-up.
- **When in doubt about whether a decision needs an ADR, ask.** The default on doubt
  is to ask, not to skip and not to write one unilaterally.
- Numbering is sequential and never reused: `NNNN-short-title-in-kebab-case.md`.
- ADRs, like everything under `docs/`, are written in English.

## Template

```markdown
# ADR-NNNN: <the decision, as a statement>

- **Status**: Proposed | Accepted | Superseded by [ADR-MMMM](./MMMM-....md)
- **Date**: YYYY-MM-DD

## Context

What situation forced a decision. What was measured or verified, and where that
evidence lives.

## Decision

What was decided, stated plainly.

## Alternatives considered

Each alternative that was genuinely on the table, and the specific reason it lost.

## Consequences

What this costs, what it makes easy, and what has to be re-verified when the
surrounding software changes.
```

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](./0001-patch-formatters-instead-of-registering-a-format.md) | Patch both formatters instead of registering a new format | Accepted | 2026-09-19 |
| [0002](./0002-add-detector-version-to-formatted-text-cache-key.md) | Add the detector version to the formatted-text cache key | Superseded by [ADR-0004](./0004-add-score-threshold-to-formatted-text-cache-key.md) | 2026-09-19 |
| [0003](./0003-forward-constructor-arguments-untouched.md) | Forward the formatter constructor's arguments untouched | Accepted | 2026-09-19 |
| [0004](./0004-add-score-threshold-to-formatted-text-cache-key.md) | Add the score threshold to the formatted-text cache key | Accepted | 2026-09-19 |
