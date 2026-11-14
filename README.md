# MapMethod

MapMethod turns a savings goal into a map made of rounded square cells. Choose a place, set the target, and fill whole cells as you save. The same SwiftUI app is built for iPhone and Mac.

## MVP

- Search for a city, district, or country; draw a custom outline; or choose the built-in Earth silhouette.
- Zoom and pan around the generated map.
- Set a target and a main cell denomination. The app suggests a starting denomination and automatically adds smaller-value cells for the remainder.
- Cell area is proportional to its amount. Cells stay whole squares with rounded corners and fit inside the selected outline.
- Fill or undo whole cells. The app records each action and its date for future history and the planned savings time-lapse.
- Create multiple maps, see saved amount and percentage, and view the most recently updated map in an iPhone or Mac widget.
- Sync goal data through the user's private iCloud CloudKit database.
- Use light depth, shadows, and spring animation when cells change state.

The time-lapse movie is a post-MVP idea. The MVP records the dated cell events needed to make it later.

## Build and run

See [docs/BUILDING.md](docs/BUILDING.md) for Xcode, signing, CloudKit, and widget setup. The project is not published to the App Store; run it directly from Xcode on your own devices.

```sh
brew install xcodegen
xcodegen generate
open MapMethod.xcodeproj
```

Available schemes: `MapMethod-iOS`, `MapMethod-macOS`, `MapMethodWidget-iOS`, and `MapMethodWidget-macOS`.

## Map data

- Place search uses Apple's MapKit search.
- Administrative outlines are looked up from OpenStreetMap through the public Overpass API after the user selects a search result. Responses are cached locally; requests are user-triggered and spaced. OpenStreetMap attribution is shown in the app. See the [Overpass API documentation](https://dev.overpass-api.de/overpass-doc/en/) and the [OpenStreetMap attribution and ODbL information](https://www.openstreetmap.org/copyright).
- The built-in Earth silhouette comes from Natural Earth's 1:110m land polygons. The dataset is public domain; its source and converter are documented in [Resources/NATURAL_EARTH.md](Resources/NATURAL_EARTH.md).

Place search needs an internet connection. If a selected place has no usable boundary, the app offers the custom drawing flow.
