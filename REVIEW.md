# REVIEW.md

Guidance for reviewing pull requests.

## Establish the review scope

Do not report an issue that is present at the merge base and unaffected by the diff, even when it violates current project rules or appears in a touched file. If the PR copies, expands, or worsens a pre-existing violation, target only the introduced or worsened portion. Repository-wide searches must establish the effects of changed symbols and artifacts; they do not expand the review into an audit of existing code.

## Check the Summary

Verify these sections appear in order:

1. `## Description`
2. `## Changes made in this PR`
3. `## Acceptance Criteria & How to Test`
4. `## Related Task (Optional)`
5. The `---` divider followed by `**For the task-synthesis pipeline.**`
6. `## Task Instruction`
7. `## Changes Made`
8. `## Self-containment & Dependencies` (optional)
9. `## Screenshots & Media` (optional)
10. `## Type of Change`
11. `## Checklist`

A missing required section is a P0 finding. Optional sections may be omitted only when they genuinely do not apply; prefer an explicit `N/A` with a reason. A preview video may additionally appear above `Description`, but it does not replace the media section when that section is applicable.

Reject summaries that retain template guidance comments, blank placeholders, or omit standard type-of-change choices or checklist attestations. Do not pass the summary based on headings alone.

## Project rules

- New code must not copy, expand, or worsen existing patterns.
- Report only introduced or worsened violations as P0 findings.
- Do not report pre-existing violations that are unchanged by the PR or require the PR to refactor them.
- For every changed feature, trace its wiring and data flow end to end against every applicable `AGENTS.md` rule. An existing pattern is not evidence of correctness when it conflicts with those rules.

## Review the code

Within the established diff scope, inspect introduced code and its directly affected callers, tests, resources, serialized references, and integrations.

1. Verify implementation and extensibility:

    - Wire dependencies explicitly without globals, hidden lookups, or cycles, and keep mutable state behind narrow owner-controlled APIs.
    - Validate changes before committing, separate gameplay truth from presentation, and define content through typed catalogs, stable IDs, and authoritative mappings.
    - New behaviors require validation, tests, and a real caller; share code only after a second use, consume every signal, and preserve voxel and persistence contracts.

2. Verify implementation quality:

    - Implement the requested behavior correctly and concisely without avoidable duplication, sharing logic between `can_x()` and `x()`.
    - Add focused tests for changed rules, transactions, persistence, deterministic generation, and behavior families; passing existing tests alone is insufficient.
    - Add no comments, unused parameters, contract-excluded defensive paths, or unrelated changes.

## Check for dead code and artifacts

For each added or renamed symbol or artifact—and existing item whose wiring changed—search its name, path, and UID, then prove reachability from production or a registered test runner. Text matches are insufficient: identify real callers and entry points for callbacks, serialized wiring, and string calls; test-only use does not prove production integration. Reject old references and compatibility shims except validated migrations, then remove unintended generated or temporary files while preserving required Godot metadata, authored assets, presets, and fixtures.

## Cross-check the summary and code

Treat every factual statement in the PR summary as a claim that must be verified against the introduced code and test evidence.

- Confirm every described behavior, rename, removal, fix, and test is present in the diff.
- Identify material code changes that are missing from or contradicted by the summary.
- Verify absolute claims such as “all,” “removed,” “replaced,” “no longer,” and “fully supported” across the repository.
- Verify claimed commands, test results, warnings, screenshots, and manual observations rather than treating checklist marks as evidence.
- Do not treat intended behavior as implemented behavior.
- Only require the summary to mention material changes, not incidental implementation details.

When they disagree:

- The code should change when it does not implement the stated requirement or promised behavior.
- The summary should change when the implementation is intentional but the description is inaccurate, incomplete, or overstated.
- If intent cannot be determined, report the exact mismatch and request clarification.

## Findings

Label every finding:

- **[P0] Blocking:** Incorrect or misleading PR summaries, summary/code mismatches, requirement or project-rule violations, correctness bugs, dead code, unintended changes, or missing or failing checks introduced or worsened by the PR.
- **[P1] Non-blocking:** Valid alternative implementations that preserve every requirement and project invariant, local maintainability improvements, incidental duplication, or performance opportunities.
- **[P2] Nits:** Misspellings, import ordering, minor naming inconsistencies, trivial simplifications, or optional documentation polish.

Only report findings supported by the diff and repository evidence. Do not report speculative problems or personal preferences, and combine findings that share the same root cause.

Your findings should be concise and easy for an engineer to digest without needing to sift through verbosity.

For example:

- **[P0] Blocking (file:line_number(s))** [concrete problem]. we should [required change].
- **[P1] Non-blocking (file:line_number(s))** [observation and consequence]. we could [suggestion].
- **[P1] Non-blocking (file:line_number(s))** Confirm this is intentional. [consequence].
- **[P2] Nit (file:line_number(s))** [symbo] has no callers. we should remove it.
- **[P0] Blocking (file:line_number(s))** The PR description says [claim], but the implementation [actual behavior]. Update it to [accurate wording].

These examples illustrate tone and structure only; they are not standardized templates. Write each comment naturally and originally for its specific context while keeping it concise, direct, and actionable.
