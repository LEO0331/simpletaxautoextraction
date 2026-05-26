# Instruction Governance Harness

Source: Harness Engineering lecture 04 warns that one giant instruction file lowers signal-to-noise ratio and hides critical constraints in the middle of long context.
Trigger: Read before adding project instructions, agent rules, recurring lessons, or workflow notes.
Expiry: Revise after any major repo reorganization or if the team adopts a different agent harness format.

## Principle

The entry point should be a router, not an encyclopedia.

Keep high-frequency, high-priority instructions in `docs/HARNESS.md`. Move specialized guidance into topical files under `docs/harness/`.

## Add-or-Route Decision

Before adding a new instruction, classify it:

| Instruction type | Location |
| --- | --- |
| Global hard constraint used by most tasks | `docs/HARNESS.md` |
| Domain-specific rule | Matching `docs/harness/*.md` |
| Historical bug lesson | Regression test or topical doc |
| One-time release note | Release checklist or issue, not harness |
| Implementation detail visible in code | Code comment or type, not harness |

## Required Metadata

Every new topical instruction should include:
- Source: why it exists.
- Trigger: when to read it.
- Expiry: when it can be deleted or revised.

## Audit Checklist

Run this audit monthly or before major releases:
- Is `docs/HARNESS.md` still short enough to scan quickly?
- Are there duplicate or conflicting instructions?
- Are old CI/release warnings still true?
- Can a historical instruction become a test instead?
- Are critical security constraints near the top of the router or in the relevant security doc?

## Signal-to-Noise Rule

If a task type would ignore an instruction more than 80% of the time, it probably belongs in a topical doc instead of the router.
