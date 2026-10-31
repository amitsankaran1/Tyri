# Scheduling and access settings — 2.3 (5)

Requested: make scheduling easier to understand, put Schedule first when creating a block, explain cooldown/break settings, and publish current screenshots in Notion with prior screenshots archived by version.

## Changes

- Creation menu: Schedule → Usage limit → NFC tag. First-block onboarding also starts with Schedule.
- New schedule drafts start with a visible weekdays 09:00–17:00 default.
- Schedule editor: start/end times, Every day/Weekdays/Weekends shortcuts, individually selected days, and a localized summary. No enable switch or seven day switches. Empty day selections cannot be saved. Existing schedules can be removed explicitly.
- Overnight copy explains that the block ends the next day and selected days specify the start day.
- “Stop early” replaces “Early disable” / “Cooldown”: each option says “Wait …”, and helper text says apps remain blocked during that wait. The countdown screen and stop action use the same language.
- “Take a break” explains the single temporary pause per session and automatic resumption. Other active blocks remain enforced.
- “Then block apps for” replaces “Lockout duration.”
- Active-block restrictions, persisted model fields, and the existing enforcement mechanisms are unchanged by the UX work.

The familiar time + repeat-days pattern follows [Apple Clock's alarm setup](https://support.apple.com/guide/iphone/set-an-alarm-iph2909d3a74/ios). The supplied screenshot could not be read because macOS denied Downloads access; the existing SwiftUI implementation was inspected directly instead.

## Validation and screenshots

Release compilation and Apple distribution signature/entitlement verification succeeded. Three existing UI cases passed. The new scheduling case passed in a focused rerun after test-only navigation and accessibility corrections, including saved repeat days and break duration after relaunch. Four current screenshots were added to Notion; 21 previous images were preserved under the versioned archive toggle. Apple accepted the 2.3 (5) upload and reported processing. Detailed evidence is in the release receipt and on the Tyri Notion page. Screenshots are real simulator captures using demo state; they do not establish physical Screen Time enforcement.
