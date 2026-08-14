<!--
GameDev Eng group-project PR template.

Keep the section headings below and their order. Replace each guidance comment
with your actual content, and delete the comment. Sections marked (Optional) may
be left out entirely if they genuinely don't apply — but prefer an explicit "N/A,
because ..." over silence.

TWO AUDIENCES. Write every PR for two readers. The first is the human reviewer who
needs to understand and verify the change. The second is the ML team's task-synthesis
pipeline, which turns our PRs (or blocks of them) into coding-agent training tasks.
That pipeline treats this repo as the "solution repository", and it needs two things
from each PR: a self-contained instruction it can turn into a task, and acceptance
criteria scoped to only the features the PR actually asked for.

Full reasoning for every section — including what each one feeds in the pipeline —
is in PR #1 of this repo, which is the worked example.

Before you request review: add a row for this PR to the PR Index table in README.md.
-->

## Description

<!--
A short narrative of what the PR does and why we need it. Lead with the feature or fix
in plain language, then the motivation: what problem it solves or what it unblocks.
Keep it to a few sentences — the details live in "Changes Made".
-->

## Changes made in this PR

<!--
List the discrete, independently-testable skills the change contains, one line each.
e.g. "(1) data-driven item registry, (2) inventory add/remove/stack model, (3) tabbed
scrolling UI, (4) reorder menu." Feature-sized PRs are fine — this list simply
compartmentalizes them, and it lets the pipeline split the PR cleanly instead of
guessing the boundaries from the diff.
-->

1.
2.

## Acceptance Criteria & How to Test

<!--
First, a bulleted list of observable pass/fail criteria, one per feature the PR asked
for ("Pressing I opens a centered panel and freezes the player", "Left/Right cycle tabs
and wrap"). Only list criteria for behavior this PR actually requested — the pipeline
writes tests from these, and off-spec criteria produce off-spec tests.

Then numbered, reproducible steps a reviewer follows to run the change and check each
criterion. Cover the main path and the notable edge cases. If there are no automated
tests, say so outright — these criteria are then the main evidence the feature behaves.
-->

**Acceptance criteria:**

-

**How to test:**

1.

## Related Task (Optional)

<!--
Link the tracking task this PR closes, e.g. `Closes T123567890`. If there isn't a formal
Task, note how the work is tracked (a planning doc, a group increment) so the change is
traceable.
-->

---

**For the task-synthesis pipeline.** The sections below are grouped for automated scraping: the task instruction, file manifest, dependencies, and media, followed by the standard PR metadata.

## Task Instruction

<!--
Restate the change as a build request, written as if you're starting from the state
before this PR. Example: "Add a tabbed inventory toggled with the I key that freezes the
player while open." Describe the observable feature, not the implementation, and don't
reference other PRs or "the previous change" unless this PR is deliberately part of a
block. It must be buildable from the base commit on its own — stray cross-references are
a known failure mode for the pipeline. Quote it as a blockquote.
-->

>

## Changes Made

<!--
A bulleted list of the key changes, by file or module. Mark each as **new** or
**modified** and say what it's responsible for, not line-by-line detail. The new-vs-
modified split tells the pipeline which files are the starting point and which are part
of the solution.
-->

-

## Self-containment & Dependencies (Optional)

<!--
A line or two: what prior state this PR builds on (e.g. an earlier feature), and whether
it's meant to stand alone or be read as part of a block. Call out anything a reader has
to already have for the change to make sense.
-->

## Screenshots & Media (Optional)

<!--
For any user-facing change, embed **before and after** screenshots of the key states,
with a one-line "what to look for" note per shot. Link a short video if motion matters.
Upload media to an approved host and link it — do not commit large binary files. If
nothing is captured yet, say so and note when it will be.

Optional because backend-only work streams may have no visual representation. But note
that anything not visible on-camera is a documented failure mode for the pipeline, which
labels task difficulty partly by how much visual understanding a change needs.
-->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that alters existing behavior)
- [ ] Refactor (no functional changes)
- [ ] Documentation update

## Checklist

<!--
Author self-attestation before requesting review. Check each item honestly. Where an item
doesn't apply, mark it N/A with a one-line reason (e.g. "N/A — no test harness in this
repo, verified manually") rather than leaving it ambiguous.
-->

- [ ] Code follows the project's style guidelines
- [ ] Performed a self-review
- [ ] Added/updated tests
- [ ] Tests pass locally
- [ ] Updated documentation (if needed)
- [ ] No new warnings introduced
- [ ] Added a row for this PR to the PR Index in `README.md`