---
name: doc-freshness-audit
description: Scan every .md in the current repo for path/file references that no longer exist on disk. Surfaces stale code-path links in README, CLAUDE.md, ARCHITECTURE.md, CONTRIBUTING.md, and docs/, so they don't mislead Claude (or a human) during the next session. Outputs a table; never auto-edits. Use after a refactor that moved or renamed files, after a package-boundary change, or before opening a PR that includes doc edits.
---

# Doc freshness audit

The goal is to catch one specific failure mode: a refactor moves `src/foo/bar.ts` to `packages/foo/src/bar.ts`, but README/CLAUDE.md/CONTRIBUTING.md still link to the old path. Future readers (Claude included) load the doc, follow the broken pointer, waste context on dead leads.

This skill is read-only. It produces a table; the user decides what to fix.

## When this is invoked

- User runs `/doc-freshness-audit` (no args)
- User runs `/doc-freshness-audit <path>` to limit to one doc
- Claude invokes after detecting a refactor (file renames in `git status`, package layout changes)

## What you do

1. **Locate the repo root**: `git rev-parse --show-toplevel`. If not in a git repo, ask the user for the directory.

2. **Discover docs to audit**:
   ```bash
   find "$ROOT" -name "*.md" \
     -not -path "*/node_modules/*" \
     -not -path "*/.git/*" \
     -not -path "*/reports/*" \
     -not -path "*/dist/*" \
     -not -path "*/build/*" \
     -not -path "*/.next/*" \
     -not -path "*/coverage/*"
   ```
   Honor `.gitignore` heuristically: if a directory is gitignored, skip it (cheap check: `git check-ignore -q <dir>`).

3. **Extract candidate references** from each doc. Three regex passes:
   - Markdown links: `\[[^\]]*\]\(([^)]+)\)` — capture group 1 is the target
   - Backtick-quoted paths: `` `([a-zA-Z0-9_./@\-]+\.(?:ts|tsx|js|jsx|sql|json|yml|yaml|md|sh|py|go|rs|toml))` ``
   - Inline path mentions starting with a known top-level dir: `\b(src|packages|sql|docs|infra|app|lib|test|tests|scripts)/[a-zA-Z0-9_./\-]+`

4. **Filter out false positives** before checking existence:
   - URLs: anything matching `^https?://`, `^mailto:`, `^#` (in-doc anchors), `^/` followed by a domain-like start
   - Generic example tokens: `<file>`, `<path>`, `…`, `...`, `EXAMPLE`
   - Tokens that have no `/` AND no `.` (likely a symbol name, not a path) — e.g. `validateSql`
   - Anything inside a fenced code block whose language is `bash`, `shell`, `sh`, or `console` — these may be example commands with intentional fake paths. *Exception*: if the path starts with one of the known top-level dirs (`src/`, `packages/` …), still check it.

5. **Resolve and check each candidate**:
   - Strip a trailing `:LINE` suffix (e.g. `packages/foo.ts:42` → `packages/foo.ts`)
   - Strip a fragment (`#anchor`)
   - If relative, resolve against the directory of the doc containing it (`dirname doc.md / path`)
   - If absolute (starts with `/`), use as-is — but warn if it leaves the repo
   - Test existence with `test -e "$resolved"`

6. **Emit one Markdown table per audited doc** (only if it has any stale refs):
   ```
   ### docs/foo.md
   | Line | Reference                       | Resolved to                       |
   | ---- | ------------------------------- | --------------------------------- |
   | 40   | src/insight/llm_provider.ts     | (missing)                         |
   | 71   | src/mcp/tools/query_workstyle.ts| (missing) — moved to packages/?   |
   ```
   For each missing path, do a one-shot `git log --diff-filter=D --name-only --pretty=format: | grep` to suggest whether it was deleted or renamed. Add the hint to the third column if found.

7. **Summary line**: `Audited N docs, M stale references across K files.` If clean, output `All references resolve.` and stop.

## What NOT to do

- Do not auto-edit any file. The user must approve each change.
- Do not flag valid external URLs even if they 404 — out of scope; this skill is for **repo-internal** path freshness.
- Do not recurse into `reports/`, `node_modules/`, or any gitignored directory. They are not part of the contract.
- Do not flag a reference that resolves to a symlink target, even if the symlink target is outside the repo.
- Do not echo every doc you audited — only the ones with findings, plus the summary line.

## Edge cases

- **Renamed file**: `git log --follow --name-status -- <old-path>` can sometimes pick up the new location. Use it for the suggestion column. Don't trust it as ground truth.
- **Glob references**: a doc might say `sql/views/*.sql`. Treat any path containing `*` or `?` as a glob and check via `compgen -G` or `ls`. Pass if at least one match exists.
- **Code-block commands**: `pnpm test src/foo.test.ts` inside a ```bash``` block. Use the rule from step 4 — apply the check only if the path starts with a known top-level dir.
- **Symlinks**: existence check via `test -e` follows symlinks; this is correct (the target should exist).
- **Case-insensitive filesystems** (macOS default): `test -e` is case-insensitive on APFS. This means a reference like `src/Foo.ts` may pass on Mac but break on a Linux CI. Out of scope to detect; mention in the summary if running on macOS as a one-line caveat.

## Reporting back to the user

Final output structure:

```
## Doc freshness audit

Audited <N> docs in <repo-root>.
<summary line>

<per-doc tables>

<one-line caveat if macOS>
```

If no findings, just:
```
## Doc freshness audit
Audited <N> docs in <repo-root>. All references resolve.
```
