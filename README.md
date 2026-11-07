<a href="https://www.kickstarter.com"><img src=".github/ksr-wordmark.svg" width="36%" alt="Kickstarter for iOS"></a>

<p>
  <a href="https://www.3daysofswiftconcurrency.com/"><img src=".github/migration-branding/3days-of-swift-concurrency.png" width="140" alt="3 Days of Swift Concurrency"></a>
  <a href="https://github.com/3DaysOfSwift/CFA-AI-Toolkit-for-iOS"><img src=".github/migration-branding/cfa-ai-toolkit.png" width="140" alt="CFA AI Toolkit for iOS"></a>
</p>

# Kickstarter Migrated to Swift Concurrency using AI

[Browse the migrated branch](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/tree/migration/cfa-swift-concurrency) · [Browse the original baseline](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/tree/main) · [Read the migration ledger](https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter/blob/migration/cfa-swift-concurrency/MIGRATION_LEDGER.md)

This repository is an independent, AI-assisted migration of [Kickstarter's open-source iOS app](https://github.com/kickstarter/ios-oss). It is an educational case study by 3 Days of Swift Concurrency, not an official Kickstarter release. The original app and its authors retain their copyright and [Apache 2.0 licence](LICENSE).

The **`migration/cfa-swift-concurrency` branch contains the migrated app**. This branch is the place to inspect, build and run the result. The repository's `main` branch preserves the upstream starting point, with an overview of the two versions.

## Clone the migration branch

```sh
git clone --branch migration/cfa-swift-concurrency --single-branch https://github.com/3DaysOfSwift/Legacy-GCD-Migration-iOS-App-Kickstarter.git
cd Legacy-GCD-Migration-iOS-App-Kickstarter
cp 'Kickstarter-iOS/3 - App Resources/Configuration/Secrets.swift.example' KsApi/Sources/KsApi/Secrets.swift
```

In the copied `KsApi/Sources/KsApi/Secrets.swift`, set `isOSS` to `true`. Open `Kickstarter.xcodeproj`, let Xcode resolve the package dependencies, select the **Kickstarter iOS** scheme and a simulator, and run the Debug build. The migration was verified using Xcode 26.2 and an iPhone Air simulator running iOS 26.2. The local secrets file is ignored by Git; do not commit credentials.

The [public-demo guide](docs/PUBLIC-DEMO.md) explains the fictional catalogue, supported browsing flows and setup. It does not require Kickstarter API keys for those flows. Login, real payments and other live operations are not a complete offline demo; the project still resolves Swift packages and is not fully offline.

## Before and after

The upstream baseline uses a UIKit application with application code spread across local Swift packages, including `Library` and `Kickstarter-Framework`. Its view models use ReactiveSwift signals and producers to connect inputs, outputs and asynchronous work.

The migrated branch keeps the existing UIKit screens and moves core app code into the application target using **Cooperative Feature Architecture (CFA)**. An AppModel composes features that own application state and workflows; view models and controllers handle presentation and invoke feature operations. Swift Concurrency provides the primary async task and cancellation model, and Observation is used for migrated observable state. Some Combine, platform callbacks and third-party SDKs remain where applicable.

```text
Kickstarter-iOS/
  1 - View/              Screens, controllers, view models and shared UI
  2 - AppModel/          Composition, features, storage and service adapters
  3 - App Resources/     Configuration, localization and app resources
  4 - Swift Extensions/  Shared extensions
ApplicationTests/        App-hosted tests and support
```

The app no longer links ReactiveSwift or ReactiveExtensions. Local packages including `KsApi`, `GraphAPI`, `Experimentation`, `KDS` and `ServerDrivenUI` remain for services, generated APIs, design and reusable rendering. See the [implementation handover](MIGRATION_COMPLETION_REPORT.md) for the structural migration and the newer [ledger](MIGRATION_LEDGER.md) for subsequent changes, including ReactiveSwift removal.

## What the migration achieved

The work moved core app code out of the two application libraries and into the CFA folder structure, migrated feature workflows towards owned async tasks, and removed ReactiveSwift from app and test targets. A fictional-data demo supports discovery, search and project browsing without private API credentials.

This was an **AI-assisted, substantially autonomous migration with human direction, review, testing and follow-up corrections**. The earliest recorded preparation was 26 October 2026 at 14:18 Bangkok time; the CFA implementation handover was recorded on 3 November at 21:44. Those checkpoints are approximately **8 days and 7 hours apart**, including interruptions and human involvement, not a measurement of active model time. ReactiveSwift removal and further review continued afterwards. GPT-6 Astra High is identifiable in screenshots for portions of the work; exact per-commit model and cost information was not recorded.

## Verification and limits

At the 3 November handover, selected existing cohorts reported **2,929 passing tests**. Following ReactiveSwift removal, separate runs on iPhone Air / iOS 26.2 passed **1,944 non-snapshot model tests**, **183 non-snapshot presentation tests**, and **39 signed keychain tests**. These are separate checkpoints and overlapping cohorts, not additive totals. The simulator build succeeded, and a limited public-demo smoke check covered discovery sorting, opening a project and searching.

The original snapshot references require an iPad mini (A17 Pro) with iOS 18.6; those comparisons were not rerun because that runtime was unavailable. Physical-device review, full visual/accessibility validation and live account/payment operations remain unverified. This case study is not a production certification, a claim of race freedom, or a warning-free Swift 6 build. See [remaining work](MIGRATION_REMAINING_WORK.md) and the [ledger](MIGRATION_LEDGER.md) for details and dated evidence.

## Credits and licence

The starting application, its assets and original documentation are from [kickstarter/ios-oss](https://github.com/kickstarter/ios-oss). Third-party notices are in [NOTICE.md](NOTICE.md). The project is available under the [Apache License 2.0](LICENSE).
