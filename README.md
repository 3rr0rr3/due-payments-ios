# Due — monthly payment organizer

Native SwiftUI iPhone app for iOS 17 or later. Includes monthly totals, recurring payments, paid/unpaid history by month, categories, editing, deletion, local JSON storage, and advance local notifications.

## Run on iPhone

On a Mac with Xcode installed:

1. Install XcodeGen with `brew install xcodegen`.
2. Run `xcodegen generate` in this folder.
3. Open `Due.xcodeproj`, select the Due target, and choose your Apple development team in Signing & Capabilities. Use a unique bundle identifier.
4. Select an iPhone simulator or connected iPhone and press Run.
5. Add a payment and tap Enable notifications to allow reminders.

## Behavior and scope

- Payments repeat monthly; days 29–31 clamp to the last valid day of shorter months.
- Paid status is recorded separately for each month. Editing a recurring payment updates its amount and due day across all displayed months.
- Amounts use the device's currency. No bank connection, automatic charge detection, currency conversion, or cloud sync is included.
- Notifications are scheduled at 9 AM local time for the next 12 months, keeping only the nearest 60 alerts. Open the app regularly to refresh this queue. Already elapsed reminder times are skipped. Notification delivery also depends on iPhone permissions and Focus settings.
- Data stays in the app's Documents directory. Deleting the app may remove its data.

## Validation

This project was authored on Windows; an Xcode build and iPhone notification validation are still required. Check creating/editing/deleting payments, paid status across months, February day clamping, persistence after relaunch, and notification permission/arrival on a real device. An app icon and production signing configuration are needed before distribution.
