# BirdCount for iOS

BirdCount is a simple, fast, offline-first bird counting app. It lets you:
- Browse a species list from a bundled taxonomy
- Quickly add counts per species with a compact bottom sheet
- Filter by a global date range (Today, Last hour, Last 7 days, All, Custom)
- View a summary and a detailed observation log
- Sync observations device-to-device (Bonjour P2P) and to the cloud
  (Sign in with Apple; manual or automatic on Wi-Fi)

## Requirements
- macOS with Xcode 15 or newer
- iOS 18.5+ Simulator or device target
- Swift 5.10+, XcodeGen (`brew install xcodegen`)

## Getting started
1) `make generate` — regenerate `BirdCount.xcodeproj` from `project.yml`
2) Open `BirdCount.xcodeproj`, select the BirdCount scheme and a simulator
3) Build and Run

Or from the command line: `make build-test`, `make test` (see `make help`).

## Project layout
- `BirdCount/Models/` — observation ledger model (`ObservationRecord`/DTO), taxonomy, import/export
- `BirdCount/Stores/` — `@Observable` state containers (observations, taxonomy, settings, date range)
- `BirdCount/Sync/` — P2P sync (Bonjour/TCP)
- `BirdCount/Cloud/` — cloud sync (Cognito + Sign in with Apple, sync service, `cloud-config.json` endpoints)
- `BirdCount/Views/` — SwiftUI views by feature (Home, Summary, Log, Settings)
- `BirdCount/Resources/` — bundled taxonomy, region checklists, cloud config
- `Tests/`, `TestsCore/` — simulator and fast-macOS test suites

## Documentation
- `Architecture.md` — app architecture and data flow
- `../docs/sync-architecture.md` — sync design (ledger model, cloud protocol, P2P coexistence)
- `AGENTS.md` — build commands and rules for AI agents
- `FASTLANE.md` — release automation
