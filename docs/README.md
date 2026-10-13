# Documentation Index

## Personal Australian Tax Workspace (proposed)

- [Product plan v1.0](product/PERSONAL_AU_TAX_WORKSPACE_PLAN.md) - supplied baseline specification, preserved unchanged.
- [Implementation gap analysis](product/IMPLEMENTATION_GAP_ANALYSIS.md) - repository evidence, proposed architecture, migration, phase mapping and implementation status.
- [Document requirements](product/DOCUMENT_REQUIREMENTS.md) - evidence coverage, parser boundaries and privacy requirements.
- [Tax source register](product/ATO_SOURCE_REGISTER.md) - source access status, year applicability and unresolved rule verification.

These documents describe future work. They do not establish implemented tax-rule coverage or verified personal tax results.

## Harness Engineering Layer

Start here for agent/workflow guidance:

- [Harness Router](HARNESS.md) - short entry point with project constraints and routing table.
- [Investment CGT Harness](harness/investment-cgt.md) - investment transaction and CGT estimate rules.
- [PDF Parsing Harness](harness/pdf-parsing.md) - property and CommSec parser guidance.
- [Firebase Security Harness](harness/firebase-security.md) - Firestore/Auth/rules constraints.
- [Testing Harness](harness/testing.md) - deterministic test strategy and CI guidance.
- [Release Harness](harness/release.md) - GitHub Pages, SEO, and release checks.
- [Instruction Governance](harness/instruction-governance.md) - how to add or split future instructions.

## Existing Architecture and Release Docs

- [Architecture Deep Dive](ARCHITECTURE_DEEP_DIVE.md)
- [System Design Deep Dive zh-TW](system-design-deep-dive.zh-TW.md)
- [Production Hardening Checklist](PRODUCTION_HARDENING_CHECKLIST.md)
