# Building MapMethod

## Generate and open the Xcode project

Requirements: macOS, Xcode 15 or newer, and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open MapMethod.xcodeproj
```

Run the `MapMethod-iOS` scheme on an iPhone or iOS Simulator, or `MapMethod-macOS` on a Mac. The app does not need to be listed in the App Store. For a personal iPhone install, connect the phone, select it in Xcode, choose a development team, and run the app directly.

For a free Personal Team install, use the `MapMethod-iOS-Local` scheme. This local variant has no iCloud or App Group entitlements, so it saves goals only on that iPhone and does not include the widget. Personal Team provisioning expires after seven days; run the scheme from Xcode again to reinstall. Use the regular `MapMethod-iOS` scheme with a configured Developer Program team for CloudKit sync and widgets.

## Enable iCloud sync and widgets

The XcodeGen project declares these identifiers in its entitlements:

- iCloud container: `iCloud.com.gwinell.mapmethod`
- App Group: `group.com.gwinell.mapmethod`
- iPhone app: `com.gwinell.mapmethod.ios`
- Mac app: `com.gwinell.mapmethod.macos`

Register the container and App Group for your Apple Developer team, assign both app identifiers to them, and enable CloudKit for the iOS and macOS app targets. Use the same team and container on both platforms. SwiftData then syncs the private savings data through CloudKit. The iOS target includes the remote-notification background mode used by CloudKit synchronization.

The widget extensions share the App Group with their host app and read a compact local snapshot. Add the `MapMethodWidget-iOS` or `MapMethodWidget-macOS` widget from the system's widget gallery.

Each savings map keeps its own ISO currency. Changing a map's currency keeps the same numeric amounts, adjusts minor units, and does not apply an exchange rate. Values round to the precision supported by the selected currency.

Unsigned local builds and iOS Simulator builds use local SwiftData storage because they do not carry the required iCloud entitlement. To test cross-device sync, run signed builds with the registered container and App Group.

## Boundary search

Place search is an explicit user action through MapKit; the app does not send keystrokes as autocomplete. After a user selects a result, MapMethod requests a simplified OpenStreetMap boundary from Nominatim and falls back to coordinate-scoped Overpass lookups. It matches localized and alternate place names, supports polygon and multipolygon shapes plus relation and closed-way boundaries, and caches the resulting outline on device. The user can instead draw a custom contour. The global `world-outline.json` asset is bundled locally.

Natural Earth source and license details are in [Resources/NATURAL_EARTH.md](../Resources/NATURAL_EARTH.md). OpenStreetMap outlines are attributed in the app and are available under the ODbL; review the [OpenStreetMap copyright page](https://www.openstreetmap.org/copyright) when redistributing the app.
