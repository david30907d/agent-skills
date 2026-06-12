---
name: comment-discipline-check
description: Audit comments in recently modified TypeScript/JavaScript files (or a path the user names) against the "only comment the WHY" rule. Flags what-style restatements, task-specific references (PR/issue numbers, "added for X flow"), and multi-line docstrings on non-public code. Reports a table; never auto-edits. Use before commit, before opening a PR, or whenever the user asks to clean up comment noise.
---

# Comment discipline check

The goal is to surface comments that **bloat context without adding insight**. A comment that restates what a well-named function already says will be re-read by every future Claude session and waste tokens. This skill catches those.

This skill is read-only. It produces a table; the user decides what to delete.

## Source of truth

Defer to the project's CLAUDE.md if it has explicit comment rules. Check (in order):

1. `<repo-root>/CLAUDE.md` — most projects have inherited these rules from Claude Code's system prompt
2. `~/.claude/CLAUDE.md` — user-level defaults
3. Built-in defaults below

The default rule (paraphrased from Claude Code's system prompt):

> Default to writing no comments. Only add one when the WHY is non-obvious: a hidden constraint, a subtle invariant, a workaround for a specific bug, behavior that would surprise a reader. Don't explain WHAT the code does — well-named identifiers already do that. Don't reference the current task, fix, or callers — those belong in the PR description and rot over time.

If CLAUDE.md has tighter or looser rules, use those.

## When this is invoked

- User runs `/comment-discipline-check` (no args) → audit staged + unstaged TS/JS files
- User runs `/comment-discipline-check <path>` → audit a specific file or directory
- User runs `/comment-discipline-check --since=<ref>` → audit files changed since `<ref>` (e.g. `main`, `HEAD~5`)
- Claude invokes after a multi-file edit pass, before reporting completion

## What you do

1. **Determine target files**:
   - Args specified: use those (resolve directories with `find <dir> -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx"`)
   - `--since=<ref>`: `git diff --name-only <ref>...HEAD --diff-filter=AM | grep -E '\.(ts|tsx|js|jsx)$'`
   - Default: union of `git diff --name-only --diff-filter=AM` (unstaged) and `git diff --name-only --cached --diff-filter=AM` (staged), filtered to TS/JS

   Skip: `*.test.ts`, `*.spec.ts`, `*.d.ts`, files under `node_modules/`, `dist/`, `build/`, `.next/`, `coverage/`. Tests legitimately need more comments; ambient declarations are different beasts.

2. **Extract comments** from each file. Use a simple line-based scan — no full TS parser needed:
   - Line comments: `//.*` anywhere on a line. Capture the comment text and the surrounding code (line before, the line itself, line after) for context.
   - Block comments: `/* ... */` (greedy across lines). Capture similarly.
   - JSDoc: `/** ... */`. **Special case** — see step 3.

   Skip:
   - Shebangs (`#!/usr/bin/env node`)
   - Inline disables (`// eslint-disable-next-line`, `// @ts-expect-error`, `// prettier-ignore`) — these are directives, not comments
   - License headers at file top (first 10 lines, matches `Copyright|License|SPDX`)
   - Type-only comments that are part of generic syntax (rare in modern TS)

3. **Classify each comment**. Verdicts:

   | Verdict | Trigger | Example |
   | --- | --- | --- |
   | **WHAT** | Restates the next line's action or names a step in obvious code | `// Increment counter`<br>`counter++` |
   | **TASK_REF** | Mentions issue/PR/ticket numbers, "added for X", "this fix", or callers | `// Fix for #1234`<br>`// Added for the new auth flow` |
   | **MULTILINE_DOC** | `/** ... */` longer than one line AND attached to a non-`export` declaration | `/**\n * Internal helper.\n * Does Y.\n */`<br>`function _helper() ...` |
   | **DEAD_CODE** | Commented-out code (looks like valid syntax inside the comment) | `// const old = foo();` |
   | **REDUNDANT_JSDOC** | JSDoc that only restates the TypeScript signature | `/** @param x The x */` on `function f(x: number)` |
   | **WHY** *(keep)* | Explains a constraint, invariant, workaround, surprising behavior | `// stripComments first — otherwise '-- INSERT' would slip through` |
   | **UNSURE** | Cannot confidently classify | Flag for human review but don't insist on removal |

   Heuristics for WHY (keep) — at least one must hold:
   - Mentions an external system, spec, bug, or version (e.g. `// Postgres rejects empty IN()`)
   - Justifies a non-obvious choice (`// inline regex faster than RegExp constructor here`)
   - Names a trap (`// must run before X; otherwise…`)
   - Documents a public API that wouldn't be obvious from types alone (on an `export`ed symbol with JSDoc that adds *behavior* info, not just type info)

4. **Emit one Markdown table per file** (only files with at least one flag):
   ```
   ### packages/foo/src/bar.ts
   | Line | Verdict | Comment | Suggestion |
   | ---- | ------- | --- | --- |
   | 42 | WHAT | `// Loop over users` | Remove — `for (const user of users)` is self-explanatory |
   | 78 | TASK_REF | `// Added for tech-debt step 3` | Remove — context belongs in commit, not code |
   | 110 | DEAD_CODE | `// const legacyPath = ...` | Remove — dead branch; restore from git if needed |
   ```

   Include up to ~3 lines of code context after the comment in a fenced block if it materially helps the verdict.

5. **Summary**: `Checked N files. Found M comments to remove or revise.` If clean, `All comments earn their place.`

## What NOT to do

- Do not auto-edit anything. Removing a comment is a 1-line edit the user can do faster than re-reading your output.
- Do not flag comments inside test files. Tests use comments to mark scenarios (`// happy path`, `// rejects trailing semicolon`) and that's correct.
- Do not flag inline disables, license headers, or shebangs.
- Do not flag JSDoc on `export`ed APIs that adds info beyond types. `/** Returns null if X is empty */` on a public function is fine.
- Do not flag comments on `interface`/`type` members that describe semantic meaning (`/** Tenant authority is best-effort; NULL for personal spots */`).
- Do not analyze every file in the repo by default. Limit to changed files.

## Edge cases

- **Generated code**: files marked `// @generated` or under a path matching `/generated/`, `/__generated__/`, `/.next/`, etc. — skip entirely.
- **TODO / FIXME / HACK**: do NOT auto-flag as WHAT. These are intentional markers. Output them in a separate "Markers found" section at the end, so the user sees them but doesn't get noise.
- **Type assertion explanations**: `// any: <reason>`, `// eslint-disable-next-line <rule>: <reason>` — keep, the reason is the WHY.
- **i18n strings inside comments** (e.g. Japanese terms documenting a column): keep. They're domain vocabulary, not code restatement.
- **Comments in JSX**: same rules; `{/* ... */}` follows the block-comment classifier.

## Output format

```
## Comment discipline check

Checked <N> files. Found <M> comments worth revising.
Rules from: <CLAUDE.md path or "built-in defaults">

<per-file tables>

### Markers found
- packages/foo/src/bar.ts:55  // TODO: support holiday master
- packages/bar/src/baz.ts:12  // FIXME: race when … (left unflagged, but visible)
```

If clean:
```
## Comment discipline check
Checked <N> files. All comments earn their place.
```
