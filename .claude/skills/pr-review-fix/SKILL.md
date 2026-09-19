---
name: "pr-review-fix"
description: "Fetch all review feedback on a GitHub PR (inline comments, review bodies, and findings embedded in a bot review's body text), verify each one against the current code, and fix the ones that are still valid using the project's test-first workflow. Use when the user asks to check, triage, or address PR review comments (e.g. 'check the review comments on PR #12', 'address the review feedback', 'PR #12の指摘をチェックして', 'レビュー指摘を直して')."
argument-hint: "PR number (e.g. 12), or leave blank to use the open PR for the current branch"
compatibility: "Requires gh CLI authenticated with repo access; the Redmine test suite, rubocop and yard for the fix step"
metadata:
  author: "radvent"
  source: "adapted from https://github.com/haru/radvent/blob/develop/.claude/skills/pr-review-fix/SKILL.md"
user-invocable: true
disable-model-invocation: false
---

# PR Review Fix

Check every review comment on a PR against the **current** state of the code,
then fix whichever ones are still genuinely valid. Do not trust a review
comment at face value — verify it, the same way a human would before acting
on someone else's feedback.

> ⚠️ Per [CLAUDE.md](../../../CLAUDE.md): this skill may edit files, run
> tests, and run lint, but it must **never** run `git commit`, `git push`, or
> create/update a PR. Stop after fixing and hand off to the user (and the
> `commit` skill) for the git step.

## User Input

```text
$ARGUMENTS
```

Treat this as the PR number if one is given. Otherwise resolve the PR for the
current branch.

## Procedure

### Step 1: Identify the target PR

- If `$ARGUMENTS` contains a number, use it directly.
- Otherwise run `gh pr view --json number,url,headRefName` on the current
  branch. If there is no open PR, tell the user and stop.

### Step 2: Gather all review feedback

Run in parallel:

```bash
gh pr view <n> --json title,url,state,body
gh pr view <n> --json reviews --jq '.reviews[] | {author: .author.login, state: .state, body: .body}'
gh api repos/{owner}/{repo}/pulls/<n>/comments --paginate \
  --jq '.[] | {user: .user.login, path: .path, line: .line, body: .body, in_reply_to: .in_reply_to_id}'
```

`gh api` resolves `{owner}/{repo}` from the current git remote automatically.

Also fetch resolved/outdated thread state via GraphQL so already-resolved
threads aren't re-litigated (GraphQL does not expand `{owner}`/`{repo}`; get
them from `gh repo view --json owner,name`):

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first:100) {
          nodes { isResolved isOutdated comments(first:1){ nodes{ path line body } } }
        }
      }
    }
  }' -F owner=<owner> -F repo=<repo> -F number=<n>
```

Skip (or de-prioritize) any finding whose thread is `isResolved: true`.

### Step 3: Extract findings embedded in review bodies

Automated reviewers (GitHub Copilot's PR review in particular) often list
**more** findings as markdown inside the review body than they post as actual
inline comments — commonly under a "Suppressed comments" heading, formatted
like:

```
**path/to/file.rb:64**
* <description of the problem>
```

Parse the review body text for this pattern and treat each block as its own
finding, in addition to the real inline comments from Step 2. Don't skip this
— relying only on the `/comments` API endpoint will silently miss findings
that only exist in the body text.

### Step 4: Compile a deduplicated finding list

Merge inline comments + parsed body findings, dropping resolved threads and
obvious duplicates (same file/line/description reported twice). Each finding
needs: reviewer, file, line, description.

### Step 5: Verify each finding against the current code — don't take it on faith

For every finding:

- Read the referenced file **as it exists now**, not as of the review's diff
  snapshot — later commits may have moved lines or already fixed the issue.
- Confirm whether the described problem is actually present: quote the
  relevant current code as evidence, not just the comment's original snippet.
- For claims about Redmine core behaviour, settle them by reading core or
  probing with `bin/rails runner` from `$REDMINE_ROOT`, not by reasoning from
  memory.
- Check the claim against the plugin's design record before accepting it:
  `docs/adr/` and the invariants in CLAUDE.md. A suggestion that contradicts
  an accepted decision (e.g. adding a `rescue` fallback, re-detecting per
  call, registering the directive as a macro, wrapping the `prepend` in
  `to_prepare`) is not Valid — classify it as Invalid and cite the ADR or
  invariant.
- Classify:
  - **Valid** — the problem is real and still present.
  - **Already fixed** — a later commit already resolved it.
  - **Invalid** — the concern doesn't hold given the actual code/context;
    explain why.
  - **Needs user judgment** — a real trade-off or design decision, not a
    clear-cut bug — don't auto-fix these.

### Step 6: Present the validity report before changing anything

Show the user a table: file:line / finding / verdict / evidence (what you
found in Step 5). This mirrors how you'd report a manual review check.

### Step 7: Fix the valid findings — test-first

Per the constitution (principle II) and CLAUDE.md, for every finding
classified **Valid**:

1. **RED** — add or extend a test that fails because of the problem the
   reviewer described. No production code changes before this exists. Run it
   and confirm it fails for the right reason.
2. **GREEN** — make the minimal implementation change to pass it. Keep to the
   coding conventions (YARD on everything, `render_switcher_logger` instead of
   `Rails.logger`, no swallowing `rescue`, English only).
3. If the fix can move a detection verdict (pattern tables, `#` line-context
   rule, code-block masking, threshold comparison, `Directive::PATTERN`),
   **bump `Detector::VERSION`** in the same change.
4. If the fix adds a new `prepend`/patched core class, or is a design decision
   that is costly to reverse, stop and ask the user — it needs an ADR, and
   CLAUDE.md says not to write one unilaterally.
5. After all valid findings are fixed, run the full suite from `$REDMINE_ROOT`
   and confirm 0 failures and C0 coverage of `lib/` ≥ 90% (currently 100%):
   ```bash
   cd /usr/local/redmine
   COVERAGE=1 bundle exec rake redmine:plugins:test NAME=redmine_render_switcher
   ```
6. Run lint and doc coverage from the plugin directory and confirm both are
   clean (plain `rubocop`, not through `bundle exec`):
   ```bash
   cd /usr/local/redmine/plugins/redmine_render_switcher
   rubocop --ignore-parent-exclusion
   bundle exec yard stats --list-undoc   # must report 100% documented
   ```

For **Needs user judgment** findings, don't guess — ask the user (or list them
clearly in the summary as left for a decision) instead of implementing a fix.

For **Invalid** / **Already fixed** findings, make no code change — just
report the reasoning.

### Step 8: Summarize and stop — do not touch git

Report:
- Total findings found, and how many were Valid / Already fixed / Invalid /
  Needs judgment.
- What was actually fixed (file-level summary).
- Confirmation that tests pass and lint is clean.

Then stop. Do **not** `git add`/`commit`/`push`/open or update the PR from
this skill — point the user at the `commit` skill (or ask them how they'd
like to proceed) once they're happy with the diff.

## Notes

- Verification (Step 5) is the point of this skill — a review comment that
  turns out to be wrong or stale should be reported as such, not blindly
  implemented.
- Apply this same procedure to human reviewers' comments too, not just bot
  reviews — only the body-parsing in Step 3 is bot-review-specific.
- If the PR is on a fork or the `gh` auth lacks access, report the failure
  clearly rather than guessing at results.
- Anything written to a committed file (tests, comments, docs) is English,
  even when the user is conversing in Japanese.
