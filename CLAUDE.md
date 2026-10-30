# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

**Tyri** is an iOS app that uses NFC tags as physical switches to toggle app blocking via iOS Screen Time APIs.

**Prerequisites**: Xcode (full version, not just Command Line Tools), iPhone with NFC (iPhone 7+), iOS 15+

**Essential workflow**:
1. Open `Tyri.xcodeproj` in Xcode
2. Build (Cmd+B) and Run (Cmd+R) on physical iPhone (NFC doesn't work on simulator)
3. For development without NFC hardware: Use `NFCManager.shared.simulateTagScan(withId: "test123")` in code

**Key files**: `TyriApp.swift` (entry point), three manager singletons in `Services/`, views in `Views/`, and Art Nouveau theme in `Views/ArtNouveauTheme.swift`

---

## Build & Development Commands

This is an Xcode-based iOS project. **Full Xcode is required** (not just Command Line Tools).

- **Build**: Open `Tyri.xcodeproj` in Xcode and use Cmd+B
- **Run on Device**: Cmd+R (requires physical iPhone with NFC - iPhone 7+)
- **Run on Simulator**: Works for UI testing only - NFC functionality requires physical device
- **Clean**: Product → Clean Build Folder in Xcode
- **Test NFC without hardware**: Call `NFCManager.shared.simulateTagScan(withId: "identifier")` in code

The project has no external dependencies (uses only iOS system frameworks) and no automated tests currently.

---

## Architecture Overview

### Core Pattern: Callback-Based Singleton Architecture

The app uses three singleton managers with a **callback coordination pattern** rather than direct coupling:

1. **AppConfigurationStore** (`Services/AppConfigurationStore.swift`)
   - Singleton managing persistent app state
   - Properties: `selectedApps` (FamilyActivitySelection), `registeredTagIdentifier`, `isBlockingEnabled`
   - `selectedApps` persists automatically via iOS system; tag and blocking state persist to UserDefaults
   - Observable: Views react automatically via `@Published` properties

2. **ScreenTimeManager** (`Services/ScreenTimeManager.swift`)
   - `@MainActor` singleton for Screen Time API interactions
   - Manages `ManagedSettingsStore` for app blocking
   - Methods: `requestAuthorization()`, `enableBlocking()`, `disableBlocking()`, `toggleBlocking()`
   - **Key insight**: Setting `store.shield.applications` blocks apps with iOS's shield screen

3. **NFCManager** (`Services/NFCManager.swift`)
   - `@MainActor` singleton for NFC tag reading via `NFCTagReaderSession`
   - Supports ISO7816, FeliCa, ISO15693, MiFare tag types
   - Tag identifiers are hex strings from hardware IDs
   - **Important**: Uses `onTagScanned` callback for loose coupling with ContentView
   - **Testing**: `simulateTagScan(withId:)` method for development without NFC hardware

### Callback Coordination Pattern

The NFCManager doesn't directly call ScreenTimeManager. Instead:
1. ContentView sets `nfcManager.onTagScanned` callback in `setupNFCHandler()`
2. When tag scanned: NFCManager invokes callback with tag ID
3. Callback in ContentView coordinates between AppConfigurationStore and ScreenTimeManager
4. This pattern keeps managers decoupled and testable

### View Architecture

- **ContentView**: Main screen with status display and scan button; sets up NFC callback
- **SettingsView**: Screen Time authorization + app selection (uses `FamilyActivityPicker`)
- **TagRegistrationView**: NFC tag registration flow
- **TypingChallengeView**: Emergency override requiring exact typing of motivational passage
- **ArtNouveauTheme**: Design system with Art Nouveau styling (organic curves, gradient colors)

### Data Flow

1. User scans NFC tag → `NFCManager` reads hardware ID
2. NFCManager invokes `onTagScanned` callback with tag ID
3. ContentView callback checks if tag is registered:
   - If not registered: Store tag ID in `AppConfigurationStore`
   - If matches registered tag: Call `ScreenTimeManager.toggleBlocking()`
4. ScreenTimeManager updates `ManagedSettingsStore.shield.applications`
5. iOS enforces blocking with shield screen

### Key Technical Details

- **ApplicationToken**: System-managed type from Family Controls. Cannot be serialized - selection persists via system, not UserDefaults
- **@MainActor**: Both ScreenTimeManager and NFCManager are MainActor-isolated for thread safety
- **Singleton injection**: All managers use `shared` singleton instances, injected as `@StateObject` in views
- **Tag identifier format**: Hex strings from tag hardware, e.g., "04a3b2c1d0e3f1"

---

## iOS Requirements & Capabilities

- **Minimum iOS**: 15.0 (required for Family Controls)
- **Device**: iPhone with NFC (iPhone 7+)
- **Xcode project capabilities** (configured in project settings):
  - NFC Tag Reading
  - Family Controls (requires special entitlement)

---

## Working with Screen Time APIs

- Authorization required via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
- Must check `authorizationStatus == .approved` before blocking
- `ManagedSettingsStore.clearAllSettings()` disables all blocking
- Custom shield screens require separate app extension (not implemented)
- App selection uses native `FamilyActivityPicker` - cannot customize this UI

---

## Working with NFC

- Always check `NFCTagReaderSession.readingAvailable` before scanning
- Tag identifiers are hardware-based and unique per physical tag
- Session invalidation patterns:
  - User cancellation: Silent (no error shown)
  - Timeout: Show error message
  - Connection failure: Show error message
- Delegate methods are `nonisolated` - use `Task { @MainActor in ... }` for UI updates
- **Development tip**: Use `simulateTagScan(withId:)` for testing without physical tags

---

## Art Nouveau Design System

The app uses a custom Art Nouveau theme (`Views/ArtNouveauTheme.swift`):
- **Colors**: Forest green, olive green, teal, gold accents, with semantic colors (error, success, warning)
- **Gradients**: Primary, success, error, and gold gradients for visual interest
- **Fonts**: System fonts with specific weight scales (avoiding Georgia due to SwiftUI limitations)
- **Components**: `ArtNouveauCard`, `ArtNouveauOrnament`, `ArtNouveauButtonStyle`
- **Visual style**: Organic curves, decorative elements, gradient overlays, shadows for depth

When adding UI elements, use the theme's predefined colors, gradients, and components for consistency.

---

## Emergency Override System

The app includes a typing challenge for emergency access when NFC tag is unavailable:

- **TypingChallengeView** (`Views/TypingChallengeView.swift`): Requires users to type a motivational passage exactly to disable blocking
- Accessible via Settings → "Emergency Access" (only visible when blocking is active)
- Provides friction to discourage casual bypass while ensuring access is always possible
- Input normalization: Case-insensitive, ignores extra whitespace for reasonable tolerance
- Passage emphasizes intentional choice and goal alignment

---

## Selected Apps Display Limitation

- Due to iOS privacy restrictions, `ApplicationToken` doesn't expose app names or icons programmatically
- `FamilyActivityPicker` shows app details in its native UI, but this info cannot be extracted
- Settings displays count (e.g., "3 Apps Selected") instead of individual app names
- Users must use the FamilyActivityPicker to see which specific apps are selected
- This is an iOS platform limitation, not a bug

---

## Development Workflow

**Commit style** (based on git history):
- Use descriptive, action-oriented commit messages
- Start with verb in present tense: "Refactor", "Enhance", "Fix", "Add"
- Be specific about what changed and why
- Example: "Refactor NFCManager to improve tag registration handling and error checking"

**Common tasks**:
- Testing NFC logic: Use `simulateTagScan` method in ContentView or directly on NFCManager
- Modifying blocking behavior: Change ScreenTimeManager methods
- UI changes: Follow Art Nouveau theme patterns
- Adding new override mechanisms: See Roadmap.md for evaluated options

---

## Roadmap Context

See `Roadmap.md` for comprehensive analysis of potential features including:
- Time-of-day automatic locks (Tier 1 - highest priority)
- Typing challenges (already implemented)
- Cooldown timers (Tier 1)
- Motion-based unlock requirements (Tier 2)
- Each feature ranked by effectiveness, feasibility, and complexity

These features would extend the existing toggle mechanism with additional friction or automation.
