# Localization Infrastructure

This document describes the localization infrastructure for the BirdCount iOS app.

## Overview

The app uses a type-safe localization system built on top of iOS's standard `NSLocalizedString` and SwiftUI's `LocalizedStringKey` functionality. This provides compile-time safety and better IDE support for localized strings.

## Files Structure

```
BirdCount/
├── Localization/
│   ├── Strings.swift                      # Type-safe string constants
└── Resources/
    └── Localizations/
        └── en.lproj/
            └── Localizable.strings         # English string definitions
```

## Usage

### 1. Basic SwiftUI Text Views

```swift
// Direct usage with SwiftUI Text
Text(Strings.General.loading)
Text(Strings.Home.title)

// For buttons and other views that need string values
Button(Strings.General.ok.string) {
    // Action
}
```

### 2. String Values for Non-SwiftUI Contexts

```swift
// Get the actual string value
let title = Strings.Home.title.string
let message = Strings.Error.network.string

// For TextFields and other components that need String
TextField(Strings.Home.Filter.placeholder.string, text: $searchText)
```

### 3. ContentUnavailableView and Complex Views

```swift
ContentUnavailableView(
    Strings.Species.List.empty.string,
    systemImage: "bird",
    description: Text(Strings.Species.List.emptyDescription)
)
```

## Adding New Strings

### 1. Add to Localizable.strings

Add the new string to `BirdCount/Resources/Localizations/en.lproj/Localizable.strings`:

```
"new.category.key" = "New String Value";
```

### 2. Add to Strings.swift

Add the corresponding constant to `BirdCount/Localization/Strings.swift`:

```swift
enum Strings {
    enum NewCategory {
        static let key = LocalizedString("new.category.key")
    }
}
```

### 3. Use in Code

```swift
Text(Strings.NewCategory.key)
// or
label.text = Strings.NewCategory.key.string
```

## String Organization

Strings are organized hierarchically by feature/screen:

- **General**: Common UI elements (OK, Cancel, Done, etc.)
- **Home**: Home screen specific strings
- **Species**: Species list related strings
- **Observation**: Observation management strings
- **Settings**: Settings screen strings
- **Summary**: Summary screen strings
- **Sync**: Synchronization related strings
- **Error**: Error messages

## Key Features

### Type Safety
- Compile-time checking prevents typos in string keys
- IDE autocompletion for all available strings
- Refactoring support

### SwiftUI Integration
- `LocalizedString` works directly with `Text` views
- Automatic `LocalizedStringKey` conversion
- Support for string interpolation

### Flexibility
- Access to raw string values via `.string` property
- Works with both SwiftUI and UIKit components
- Compatible with standard iOS localization tools

## Future Enhancements

### Additional Languages
To add support for additional languages:

1. Create new `.lproj` directories (e.g., `es.lproj/`, `fr.lproj/`)
2. Copy `Localizable.strings` and translate the values
3. Update `project.yml` to include the new language codes in `CFBundleLocalizations`
4. Regenerate the Xcode project

### String Interpolation
The system supports string interpolation for dynamic content:

```swift
// In Localizable.strings:
"user.greeting" = "Hello, %@!";

// In code:
let greeting = String(format: Strings.User.greeting.string, userName)
```

## Migration Strategy

When migrating existing hardcoded strings:

1. Identify the string and determine its appropriate category
2. Add it to `Localizable.strings` with a descriptive key
3. Add the constant to `Strings.swift`
4. Replace the hardcoded string with the new constant
5. Test to ensure the string displays correctly

## Best Practices

1. **Use descriptive keys**: `"home.filter.placeholder"` rather than `"filter"`
2. **Group related strings**: Organize by feature or screen
3. **Keep strings atomic**: Don't concatenate localized strings
4. **Provide context**: Use comments in `.strings` files for translator context
5. **Test thoroughly**: Verify strings display correctly in all contexts
