---
name: gen-test
description: Generate comprehensive Vitest test cases for a TypeScript file. Reads the target source, identifies pure functions vs IO-bound code, writes a co-located *.test.ts with happy-path, edge-case, and error-path coverage. User-invocable as /gen-test <path>.
disable-model-invocation: true
---

# gen-test

Generate a comprehensive Vitest test file for the TypeScript module the user names.

## When this skill is invoked

The user runs `/gen-test <path-to-file.ts>`. The argument is the absolute or repo-relative path of the file to test.

## What you do

1. **Read the target file.** Identify:
   - **Pure functions** (no IO, no global state, no `process.env` reads at call time) → high-value unit tests
   - **IO-bound functions** (DB queries, network, file system, env reads at call time) → recommend integration boundary, write a small unit shim only if a pure helper exists inside
   - **Exports vs internal helpers** → tests target exports; internal helpers are covered transitively

2. **Detect the project's test conventions** by looking at:
   - `vitest.config.*` or `jest.config.*` to confirm framework
   - Any existing `*.test.ts` in the repo for import style, naming, helper patterns
   - `tsconfig.json` for `allowImportingTsExtensions` — if true, imports must use the `.ts` suffix (this matters for ESM TS projects)

3. **Write the test file** next to the source as `<basename>.test.ts`:
   - Use `describe` per function/export
   - One `it()` per behavior, not per assertion (multiple `expect()` per `it()` is fine)
   - Cover at minimum: happy path, each branch / each thrown-error path, boundary inputs (empty string, undefined, large input where relevant), case sensitivity if string parsing is involved
   - For security-critical allow-list / validator functions: enumerate **every** rejected case (each forbidden token, each malformed input pattern)
   - Use `vi.stubEnv` + `afterEach(() => vi.unstubAllEnvs())` for env-var dependent code — never mutate `process.env` directly
   - Do **not** mock the database, real HTTP, or anything where the test would be meaningless without verifying the real boundary. Skip those with a `// integration: covered separately` comment instead

4. **Run the tests once** with `pnpm test <new-file>` (or the project's equivalent) to confirm they pass before reporting done.

5. **Report** a one-paragraph summary: how many tests, which coverage targets they hit, and which parts of the file are deliberately not covered (and why).

## What not to do

- Do not refactor the source under test to "make it testable" — flag the issue, propose the refactor, but don't ship it in the same change.
- Do not write trivial tests that just re-state the implementation (e.g., asserting that a one-line getter returns its argument).
- Do not chase 100% coverage on IO-bound code by mocking everything; integration tests are the right tool.
- Do not add commentary inside test files explaining what each assertion does — well-named `it()` blocks document themselves.

## Output format

The deliverable is a Vitest test file. After writing it, summarize:
- File created
- Number of `describe` blocks and `it` blocks
- Coverage targets hit (pure functions named)
- Anything intentionally skipped, with reason
