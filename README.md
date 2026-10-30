# Tyri - Design Documentation

## App Overview

**Tyri** is an iOS app that uses NFC tags to toggle app blocking on and off. Users register an NFC tag, select apps to block, and then scan the tag to instantly enable or disable blocking for those apps. The app leverages iOS Screen Time APIs to enforce app blocking.

### Core Concept
- **Physical trigger**: NFC tag acts as a physical switch
- **Toggle behavior**: Each scan toggles blocking on/off
- **Screen Time integration**: Uses Apple's Family Controls framework for app blocking
- **Simple workflow**: Register tag → Select apps → Scan to toggle

---

## Technical Architecture

### Platform & Framework
- **Platform**: iOS (iPhone only - NFC required)
- **Framework**: SwiftUI
- **Language**: Swift
- **Minimum iOS Version**: iOS 15+ (Family Controls requires iOS 15+)

### Key Technologies
- **Family Controls**: Screen Time authorization and app selection
- **ManagedSettings**: App blocking enforcement
- **CoreNFC**: NFC tag reading (foreground sessions)
- **Combine**: Reactive state management

### App Structure
```
Tyri/
├── TyriApp.swift               # App entry point
├── ContentView.swift           # Main screen
├── Views/
│   ├── SettingsView.swift      # App selection screen
│   └── TagRegistrationView.swift  # NFC tag registration
└── Services/
    ├── ScreenTimeManager.swift  # Screen Time API wrapper
    ├── NFCManager.swift        # NFC reading logic
    └── AppConfigurationStore.swift  # State management
```

---

## User Flows

### Initial Setup Flow
1. User opens app → Sees main screen with status indicators
2. User taps "Settings" → Requests Screen Time authorization
3. User grants permission → Can select apps to block
4. User selects apps → Returns to main screen
5. User taps "Manage NFC Tag" → Registers NFC tag
6. User scans tag → Tag registered, ready to use

### Daily Use Flow
1. User opens the app and scans the registered NFC tag
2. App detects tag matches registered identifier
3. App toggles blocking state (on ↔ off)
4. If blocking enabled: Selected apps show shield screen
5. If blocking disabled: Apps work normally

---

## Screen Breakdown

### 1. Main Screen (ContentView)

**Layout**: Vertical stack with status section, status rows, and action buttons

#### Visual Hierarchy (Top to Bottom)
1. **Status Section** (Top, 40pt padding)
   - Large icon: `lock.shield.fill` (red) or `lock.shield` (gray)
   - Size: 80pt
   - Title: "Blocking Active" or "Blocking Inactive" (Bold, Title font)
   - Subtitle: Status message (Subheadline, secondary color)

2. **Status Rows** (Middle, 12pt spacing between rows)
   - Three status cards in vertical stack
   - Each card: Icon + Title + Status text
   - Background: System gray 6
   - Corner radius: 10pt
   - Padding: Standard

3. **Action Buttons** (Bottom, 20pt bottom padding)
   - Primary: "Settings" button (bordered prominent, large)
   - Secondary: "Manage NFC Tag" button (bordered, large)
   - Spacing: 12pt between buttons

#### Status Row Component
- **Layout**: Horizontal stack
- **Icon**: SF Symbol (checkmark.circle.fill = green, xmark.circle.fill = red)
- **Icon size**: Title 3 font
- **Text**: 
  - Title: Headline font
  - Status: Caption font, secondary color
- **Alignment**: Left-aligned text, icon on left, spacer on right

#### Status Indicators
1. **Screen Time**
   - Icon: Green checkmark (approved) / Red X (not approved)
   - Status: "Authorized" or "Not Authorized"

2. **Apps Selected**
   - Icon: Green checkmark (has apps) / Red X (no apps)
   - Status: "X apps" or "No apps selected"

3. **NFC Tag**
   - Icon: Green checkmark (registered) / Red X (not registered)
   - Status: "Registered" or "Not Registered"

#### Navigation
- Title: "Tyri"
- Sheet modals for Settings and Tag Registration

---

### 2. Settings Screen (SettingsView)

**Layout**: Form-based list view

#### Structure
- **Navigation**: Title "Settings", standard navigation bar
- **Form Section**: "App Selection"
  - Header: "App Selection"
  - Footer: Help text (when authorized)

#### Content States

**State 1: Not Authorized**
- Card with:
  - Title: "Screen Time authorization required" (Headline)
  - Description: Permission explanation (Caption, secondary)
  - Button: "Request Authorization" (Bordered prominent)
- Vertical padding: 8pt

**State 2: Authorized**
- Button: "Select Apps to Block"
  - Layout: HStack with title, spacer, count badge, chevron
  - Count badge: Shows "X selected" (secondary color)
  - Chevron: Right-aligned (Caption font)
- Conditional button: "Clear Selection" (Destructive role)
  - Only shown when apps are selected

#### Family Activity Picker
- Native iOS picker (sheet modal)
- Triggered by "Select Apps to Block" button
- Returns selected apps as ApplicationToken set

---

### 3. Tag Registration Screen (TagRegistrationView)

**Layout**: Centered vertical stack with conditional states

#### State 1: Tag Not Registered
- **Icon**: `sensor.tag.radiowaves.forward.fill` (60pt, blue)
- **Title**: "Register NFC Tag" (Title 2, semibold)
- **Description**: Instructions (Subheadline, secondary, center-aligned)
- **Button**: "Start Scanning" (Bordered prominent, large)
  - Icon: `sensor.tag.radiowaves.forward`
- **Error message**: Red text (Caption) if error occurs

#### State 2: Scanning Active
- **Progress indicator**: Large (1.5x scale)
- **Text**: "Scanning for NFC tag..." (Caption, secondary)
- **Button**: "Cancel" (Bordered)

#### State 3: Tag Registered
- **Icon**: `checkmark.circle.fill` (60pt, green)
- **Title**: "Tag Registered" (Title 2, semibold)
- **Description**: Confirmation message (Subheadline, secondary, center-aligned)
- **Button**: "Unregister Tag" (Destructive role, bordered)

#### Navigation
- Title: "NFC Tag" (inline display mode)
- Toolbar: "Done" button (trailing)

---

## UI Components & Design System

### Colors
- **Primary**: System blue (buttons)
- **Success**: Green (checkmarks, registered state)
- **Error**: Red (X marks, error messages, blocking active)
- **Inactive**: Gray (shield icon when inactive)
- **Background**: System gray 6 (status cards)
- **Text**: System colors (primary, secondary)

### Typography
- **Title**: System title font, bold
- **Title 2**: System title 2 font, semibold
- **Headline**: System headline font
- **Subheadline**: System subheadline font
- **Caption**: System caption font
- **Caption 2**: System caption 2 font

### Spacing
- **Section spacing**: 32pt (main screen)
- **Card spacing**: 12pt (status rows)
- **Button spacing**: 12pt
- **Content padding**: 16-24pt
- **Top padding**: 40pt (main screen status section)
- **Bottom padding**: 20pt (action buttons)

### Icons (SF Symbols)
- `lock.shield.fill` / `lock.shield` - Main status
- `checkmark.circle.fill` - Success/complete
- `xmark.circle.fill` - Error/incomplete
- `sensor.tag.radiowaves.forward` / `.fill` - NFC tag
- `gear` - Settings
- `chevron.right` - Navigation indicator

### Button Styles
- **Bordered Prominent**: Primary actions (Settings, Start Scanning)
- **Bordered**: Secondary actions (Manage NFC Tag, Cancel)
- **Destructive**: Destructive actions (Unregister, Clear Selection)
- **Size**: Large control size for main actions

### Card Design
- **Background**: System gray 6
- **Corner radius**: 10pt
- **Padding**: Standard system padding
- **Layout**: Horizontal stack with icon, text, spacer

---

## State Management

### AppConfigurationStore (Singleton)
- `selectedApps`: FamilyActivitySelection (persisted automatically by iOS)
- `registeredTagIdentifier`: String?
- `isBlockingEnabled`: Bool
- Persists tag and blocking state to UserDefaults

### ScreenTimeManager (Singleton, MainActor)
- `authorizationStatus`: AuthorizationStatus
- Manages ManagedSettingsStore
- Handles blocking enable/disable/toggle

### NFCManager (Singleton)
- `isScanning`: Bool
- `lastScannedTag`: String?
- `errorMessage`: String?
- Manages NFCNDEFReaderSession

---

## Key Interactions

### NFC Tag Scanning
- **Foreground only**: User initiates a scan from the main screen or Tag Registration view; the app must be open
- **Matching**: Compares scanned tag identifier with registered identifier
- **Action**: Toggles blocking if match found

### App Blocking
- **Enable**: Sets `store.shield.applications` with selected apps
- **Disable**: Calls `store.clearAllSettings()`
- **Visual**: iOS shows default shield screen when blocked app is opened
- **Persistence**: Blocking state persists across app launches

### Authorization Flow
- **Request**: Shows native iOS permission dialog
- **Status**: Observable property updates UI automatically
- **Required**: Must be approved before app selection works

---

## Design Considerations for Wireframing

### Screen Sizes
- Primary: iPhone (all sizes)
- Focus: Portrait orientation
- Safe areas: Respect top/bottom safe areas

### Accessibility
- Dynamic type support (system fonts)
- Color contrast: Use system colors for accessibility
- VoiceOver: All interactive elements should be accessible

### Visual Hierarchy
1. **Status icon** - Largest, most prominent
2. **Status title** - Clear, bold
3. **Status rows** - Organized, scannable
4. **Action buttons** - Clear, accessible

### Empty States
- No apps selected: Show "No apps selected" status
- Tag not registered: Show registration instructions
- Not authorized: Show authorization prompt

### Loading States
- NFC scanning: Show progress indicator
- Authorization: Native iOS dialog (no custom UI)

### Error States
- NFC errors: Red text below scanning button
- Authorization denied: Show request button again
- No NFC support: Error message in NFC manager

---

## Technical Constraints

### iOS Requirements
- **NFC**: Requires iPhone with NFC (iPhone 7+)
- **Family Controls**: Requires iOS 15+
- **Capabilities**:
  - NFC Tag Reading
  - Family Controls (Development/Distribution)

### Limitations
- **App Selection**: Uses native FamilyActivityPicker (cannot customize)
- **Shield Screen**: Uses default iOS shield (customization requires app extension)
- **Foreground-only NFC**: Tag scans require the app to be open; no lock-screen tap-to-toggle
- **Token Persistence**: ApplicationToken managed by system, not directly storable

### Permissions Required
1. **Screen Time**: User must grant Family Controls permission
2. **NFC**: Automatically available on supported devices

---

## User Experience Notes

### Onboarding
- First launch: User sees all status indicators as incomplete
- Natural flow: Settings → Tag Registration → Ready to use
- Clear feedback: Visual status indicators show setup progress

### Daily Use
- **Simple**: Just scan tag to toggle
- **Fast**: Instant toggle response
- **Reliable**: Tag matching ensures only registered tag works
- **Visual feedback**: Main screen shows current blocking state

### Edge Cases
- **Multiple tags**: Only registered tag triggers toggle
- **No apps selected**: Blocking toggle does nothing
- **Tag unregistered**: Scanning does nothing
- **Authorization revoked**: Must re-authorize in Settings

---

## Future Enhancement Ideas

### Potential Features
- Multiple tag support (different tags for different app sets)
- Custom shield configurations (requires app extension)
- Blocking schedules (time-based blocking)
- Statistics (blocking duration, frequency)
- Tag customization (name tags, assign purposes)

### UI Improvements
- Animations for state transitions
- Haptic feedback on tag scan
- Visual feedback during NFC scanning
- Onboarding tutorial
- Settings for customization

---

## Export Notes for Figma

### Recommended Frame Sizes
- iPhone 14 Pro (390 × 844) - Standard
- iPhone SE (375 × 667) - Smallest
- iPhone 14 Pro Max (430 × 932) - Largest

### Component Structure
1. **Main Screen** - Full screen with all states
2. **Settings Screen** - Form layout with both states
3. **Tag Registration** - Three states (not registered, scanning, registered)
4. **Status Row** - Reusable component (complete/incomplete variants)
5. **Buttons** - Primary, secondary, destructive variants

### Design Tokens
- Use iOS system colors (light/dark mode support)
- SF Symbols for all icons
- System typography scale
- Standard iOS spacing (8pt grid recommended)

---

## Summary

Tyri is a focused, single-purpose app with a clean, status-driven interface. The design emphasizes clarity and simplicity, with clear visual feedback for all states. The three-screen architecture (Main, Settings, Tag Registration) keeps the user flow straightforward and the UI uncluttered.

The app's strength is its physical interaction model (NFC tag) combined with iOS's robust app blocking system, creating a unique and effective solution for managing app access.
