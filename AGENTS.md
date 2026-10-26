# CFA migration working agreement

CFA workflow: established-product maintenance.

- Migrate to Cooperative Feature Architecture and Swift Concurrency one feature
  at a time. Preserve existing UIKit/SwiftUI screens, navigation, branding,
  accessibility, storage and target identifiers. No redesign is implied.
- Keep behaviour requirements in `MIGRATION_BEHAVIOUR_CONTRACT.md` and execution
  ownership/progress in `MIGRATION_LEDGER.md`.
- Keep opt-in migration case-study evidence outside this application checkout,
  in the sibling `Migration Evidence` workspace. Never copy credentials or raw
  push/device identifiers into that evidence.
- Commit completed, verified checkpoints. Do not automatically push or publish.
- Attribute new authored material to Matthew Thomas.
- Keep public demo configuration Debug-only. Never stage `Secrets.swift`.
- Do not disable snapshot reference-device checks globally to run logic tests.
  Only explicitly non-visual suites may opt out; record their actual runtime.
