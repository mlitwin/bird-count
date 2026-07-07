# BirdCount for iOS

BirdCount is a simple, fast, offline-first bird counting app. It lets you:
- Browse a species list from a bundled taxonomy
- Quickly add counts per species with a compact bottom sheet
- Filter by a global date range (Today, Last hour, Last 7 days, All, Custom)
- View a summary and a detailed observation log

## Requirements
- macOS with Xcode 15 or newer (iOS 17 SDK recommended)
- iOS 17+ device or Simulator target
- Swift 5.9+

## Project layout
- `BirdCount/` — Xcode project and SwiftUI source
	- `Models/ObservationRecord.swift` — Observation model (begin/end, count)
	- `Stores/ObservationStore.swift` — In-memory store, persistence, derived counts
	- `Views/Components/` — Reusable UI (RangeSelectorView, CountAdjustSheet, ObservationRecordView)
	- `Views/Home`, `Views/Summary` — Main tabs
	- `Resources/ios_taxonomy_min.json` — Bundled minimal taxonomy
    - `Scripts/generate_ios_taxonomy.mjs` — Helper to generate taxonomy JSON (optional)

## Getting started
1) Open `ios/BirdCount/BirdCount/BirdCount.xcodeproj` in Xcode.
2) Select the BirdCount scheme and an iOS 17+ Simulator (or a device).
3) Build and Run.
