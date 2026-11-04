# Privacy Policy

## Overview

Tyri is designed with privacy in mind. This app does not collect, transmit, or store your personal information on any external servers.

## Data Collection

Tyri stores the following information locally on your device:

- **NFC Tag Identifier**: A unique identifier from your registered NFC tag, stored locally to recognize your tag when scanned
- **App Selection**: Your selected apps to block, managed by iOS Screen Time APIs and stored locally by the system
- **Blocking State**: Whether blocking is currently enabled or disabled, stored locally

All data is stored exclusively on your device using iOS UserDefaults and system-managed storage. No data is transmitted to external servers or third parties.

## Permissions

Tyri requires the following iOS permissions:

- **Screen Time Authorization**: Required to block apps using iOS Family Controls framework. This permission is managed entirely by iOS and can be revoked at any time in Settings.
- **NFC Access**: Required to read NFC tags. NFC tag identifiers are only used locally to match your registered tag.

## Data Sharing

Tyri does not share any data with third parties. All information remains on your device and is never transmitted over the network.

## Data Deletion

You can delete all app data at any time by:
- Unregistering your NFC tag in the app settings
- Clearing your app selection in the app settings
- Deleting the app from your device

## Contact

If you have questions about this privacy policy, please contact the developer through the App Store.

## Updates

This privacy policy may be updated periodically. The current version is always available in the app or on the project repository.

---

Last updated: January 2025

## Optional natural-language block descriptions

When you use the optional description flow, Tyri sends your description, saved-list names and identifiers, locale, and time zone to its hosted interpretation service. App and category selection tokens stay on your device. You review the interpretation before saving a block. Manual list and block creation remain available.

The service uses Apple's App Attest to verify genuine app requests without a user account. It stores device public keys, attestation receipts, replay counters, short-lived challenges, and request-budget counters. Challenge records are removed after expiry plus one hour; budget records, including daily hashed network-address keys, are removed after two days. Device enrollment records remain for verification. The Tyri service does not persist descriptions or list names in its database or application logs.

The interpretation provider is still being evaluated for this development version; model execution is not enabled. This policy must name the selected provider and its processing/retention terms before live interpretation is enabled.
