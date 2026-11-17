import Foundation
import MapKit

struct PlaceSearchResult: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var coordinate: GeoCoordinate
}

@MainActor
final class PlaceSearchService {
    func search(_ query: String) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Include localities and points of interest, not only street addresses.
        if #available(iOS 18, macOS 15, *) {
            request.resultTypes = [.address, .pointOfInterest, .physicalFeature]
        } else {
            request.resultTypes = [.address, .pointOfInterest]
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let placemark = item.placemark
            let subtitle = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .filter { $0 != name }
                .uniqued()
                .joined(separator: ", ")
            let coordinate = item.placemark.coordinate
            return PlaceSearchResult(
                id: "\(name)|\(coordinate.latitude)|\(coordinate.longitude)",
                name: name,
                subtitle: subtitle,
                coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }
}

actor OverpassBoundaryService {
    static let shared = OverpassBoundaryService()

    private let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!
    ]
    private let cacheURL: URL
    private var cache: [String: MapOutline]
    private var preferredEndpointIndex = 0
    private var lastNominatimRequestAt: Date?
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 22
        session = URLSession(configuration: configuration)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MapMethod", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("boundaries.json")
        if let data = try? Data(contentsOf: cacheURL),
           let stored = try? JSONDecoder().decode([String: MapOutline].self, from: data) {
            cache = stored
        } else {
            cache = [:]
        }
    }

    func outline(for place: PlaceSearchResult) async throws -> MapOutline {
        let normalizedName = place.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let key = "\(normalizedName)|\(place.coordinate.latitude.rounded(toPlaces: 3))|\(place.coordinate.longitude.rounded(toPlaces: 3))"
        if let saved = cache[key] { return saved }

        do {
            // Nominatim returns the simplified boundary in one user-triggered request.
            let outline = try await nominatimOutline(for: place)
            store(outline, for: key)
            return outline
        } catch {
            // Overpass can still resolve places that Nominatim doesn't return by name.
            do {
                let outline = try await overpassOutline(for: place)
                store(outline, for: key)
                return outline
            } catch let boundaryError as BoundaryLookupError {
                switch boundaryError {
                case .noBoundary, .invalidGeometry:
                    throw boundaryError
                default:
                    throw BoundaryLookupError.lookupFailed(place.name)
                }
            } catch {
                throw BoundaryLookupError.lookupFailed(place.name)
            }
        }
    }

    private func store(_ outline: MapOutline, for key: String) {
        cache[key] = outline
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func overpassOutline(for place: PlaceSearchResult) async throws -> MapOutline {
        // Search boundaries that contain the selected MapKit result. This avoids a
        // global name lookup and still works when Apple and OSM use different names.
        let latitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), place.coordinate.latitude)
        let longitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), place.coordinate.longitude)
        let searchQuery = """
        [out:json][timeout:15];
        is_in(\(latitude),\(longitude))->.areas;
        (
          relation(pivot.areas)["boundary"="administrative"];
          way(pivot.areas)["boundary"="administrative"];
        );
        out center tags;
        """
        let candidates = try await request(searchQuery).elements.filter { $0.type == "relation" || $0.type == "way" }
        guard let selected = candidates
            .filter({ $0.matches(place.name) })
            .min(by: { distance($0.center, to: place.coordinate) < distance($1.center, to: place.coordinate) }) else {
            throw BoundaryLookupError.noBoundary(place.name)
        }

        // Public Overpass instances are shared community infrastructure. Keep lookups user-triggered and spaced.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let objectType = selected.type == "relation" ? "relation" : "way"
        let geometryQuery = "[out:json][timeout:20];\n\(objectType)(\(selected.id));\nout geom;"
        let response = try await request(geometryQuery)
        guard let boundary = response.elements.first(where: { $0.id == selected.id && $0.type == selected.type }) else {
            throw BoundaryLookupError.noBoundary(place.name)
        }

        let rings: [(points: [GeoCoordinate], isHole: Bool)]
        if selected.type == "relation" {
            rings = Self.rings(from: boundary.members ?? [])
        } else if let geometry = boundary.geometry {
            rings = [(points: geometry.map { GeoCoordinate(latitude: $0.lat, longitude: $0.lon) }, isHole: false)]
        } else {
            rings = []
        }
        guard let outline = MapOutline.fromGeographicRings(rings, name: place.name), outline.area > 0 else {
            throw BoundaryLookupError.invalidGeometry(place.name)
        }
        return outline
    }

    private func nominatimOutline(for place: PlaceSearchResult) async throws -> MapOutline {
        if let lastRequest = lastNominatimRequestAt {
            let remaining = 1 - Date.now.timeIntervalSince(lastRequest)
            if remaining > 0 {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastNominatimRequestAt = .now

        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: place.name),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "polygon_geojson", value: "1"),
            URLQueryItem(name: "polygon_threshold", value: "0.02"),
            URLQueryItem(name: "namedetails", value: "1"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { throw BoundaryLookupError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MapMethod/0.1.0 (https://github.com/gwinell/mapMethod)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BoundaryLookupError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw BoundaryLookupError.server(response.statusCode) }
        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BoundaryLookupError.invalidResponse
        }

        let candidates = results.compactMap(NominatimBoundary.init(json:))
            .filter { $0.matches(place.name) && $0.rings != nil }
        guard let selected = candidates.sorted(by: {
            if $0.contains(place.coordinate) != $1.contains(place.coordinate) {
                return $0.contains(place.coordinate)
            }
            if $0.isAdministrative != $1.isAdministrative { return $0.isAdministrative }
            return distance($0.center, to: place.coordinate) < distance($1.center, to: place.coordinate)
        }).first, let rings = selected.rings,
        let outline = MapOutline.fromGeographicRings(rings, name: place.name), outline.area > 0 else {
            throw BoundaryLookupError.noBoundary(place.name)
        }
        return outline
    }

    private func request(_ query: String) async throws -> OverpassResponse {
        var lastError: Error?
        for offset in endpoints.indices {
            let index = (preferredEndpointIndex + offset) % endpoints.count
            var request = URLRequest(url: endpoints[index], timeoutInterval: 18)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("MapMethod/0.1.0 (https://github.com/gwinell/mapMethod)", forHTTPHeaderField: "User-Agent")
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "data", value: query)]
            request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw BoundaryLookupError.invalidResponse }
                guard (200..<300).contains(response.statusCode) else {
                    let error = BoundaryLookupError.server(response.statusCode)
                    // A malformed query or rejected request will fail identically on another server.
                    if (400..<500).contains(response.statusCode), response.statusCode != 408, response.statusCode != 429 {
                        throw error
                    }
                    lastError = error
                    continue
                }
                do {
                    let value = try JSONDecoder().decode(OverpassResponse.self, from: data)
                    preferredEndpointIndex = index
                    return value
                } catch {
                    lastError = BoundaryLookupError.invalidResponse
                }
            } catch let error as BoundaryLookupError {
                throw error
            } catch {
                lastError = error
            }
        }
        if let boundaryError = lastError as? BoundaryLookupError { throw boundaryError }
        throw BoundaryLookupError.unavailable
    }

    private func distance(_ center: OverpassCoordinate?, to coordinate: GeoCoordinate) -> Double {
        guard let center else { return .greatestFiniteMagnitude }
        return distance(GeoCoordinate(latitude: center.lat, longitude: center.lon), to: coordinate)
    }

    private func distance(_ center: GeoCoordinate, to coordinate: GeoCoordinate) -> Double {
        let latitudeDelta = center.latitude - coordinate.latitude
        let longitudeDelta = (center.longitude - coordinate.longitude) * cos(coordinate.latitude * .pi / 180)
        return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta
    }

    private static func rings(from members: [OverpassMember]) -> [(points: [GeoCoordinate], isHole: Bool)] {
        let outer = assemble(members.filter { $0.role == "outer" }.compactMap(\.geometry))
        let inner = assemble(members.filter { $0.role == "inner" }.compactMap(\.geometry))
        return outer.map { (points: $0, isHole: false) } + inner.map { (points: $0, isHole: true) }
    }

    private static func assemble(_ source: [[OverpassCoordinate]]) -> [[GeoCoordinate]] {
        var remaining = source.map { $0.map { GeoCoordinate(latitude: $0.lat, longitude: $0.lon) } }
            .filter { $0.count >= 2 }
        var rings: [[GeoCoordinate]] = []

        while !remaining.isEmpty {
            var chain = remaining.removeFirst()
            var attempts = 0
            while !same(chain.first, chain.last), attempts < source.count + 4 {
                attempts += 1
                var match: (index: Int, points: [GeoCoordinate], append: Bool)?
                for index in remaining.indices {
                    let segment = remaining[index]
                    if same(chain.last, segment.first) {
                        match = (index, Array(segment.dropFirst()), true)
                    } else if same(chain.last, segment.last) {
                        match = (index, Array(segment.dropLast().reversed()), true)
                    } else if same(chain.first, segment.last) {
                        match = (index, Array(segment.dropLast()), false)
                    } else if same(chain.first, segment.first) {
                        match = (index, Array(segment.dropFirst().reversed()), false)
                    }
                    if match != nil { break }
                }
                guard let match else { break }
                remaining.remove(at: match.index)
                if match.append {
                    chain.append(contentsOf: match.points)
                } else {
                    chain.insert(contentsOf: match.points, at: 0)
                }
            }
            if chain.count >= 4, same(chain.first, chain.last) {
                rings.append(chain)
            }
        }
        return rings
    }

    private static func same(_ lhs: GeoCoordinate?, _ rhs: GeoCoordinate?) -> Bool {
        guard let lhs, let rhs else { return false }
        return abs(lhs.latitude - rhs.latitude) < 0.000_000_1 && abs(lhs.longitude - rhs.longitude) < 0.000_000_1
    }
}

enum BoundaryLookupError: LocalizedError {
    case noBoundary(String)
    case invalidGeometry(String)
    case invalidResponse
    case server(Int)
    case unavailable
    case lookupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBoundary(let name): return "Рядом с результатом «\(name)» не найден административный контур. Выберите другой результат или нарисуйте его вручную."
        case .invalidGeometry(let name): return "Контур «\(name)» не удалось обработать. Можно нарисовать его вручную."
        case .invalidResponse: return "Сервис границ прислал некорректный ответ. Попробуйте позже."
        case .server(let status): return "Сервис границ временно недоступен (\(status)). Попробуйте позже или нарисуйте контур вручную."
        case .unavailable: return "Не удалось подключиться к сервису границ. Проверьте интернет или нарисуйте контур вручную."
        case .lookupFailed(let name): return "Не удалось получить контур «\(name)» через OpenStreetMap. Проверьте подключение, выберите другой результат или нарисуйте контур вручную."
        }
    }
}

private struct OverpassResponse: Decodable {
    var elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    var type: String
    var id: Int64
    var center: OverpassCoordinate?
    var members: [OverpassMember]?
    var tags: [String: String]?
    var geometry: [OverpassCoordinate]?

    func matches(_ searchName: String) -> Bool {
        let searchableKeys = ["name", "official_name", "short_name", "alt_name", "loc_name", "int_name"]
        let aliases = (tags ?? [:]).filter { key, _ in
            searchableKeys.contains(key) || key.hasPrefix("name:") || key.hasPrefix("alt_name:") || key.hasPrefix("official_name:")
        }.values
        let normalizedSearch = Self.normalized(searchName)
        guard !normalizedSearch.isEmpty else { return false }
        return aliases
            .flatMap { $0.split(separator: ";").map(String.init) }
            .contains { Self.normalized($0) == normalizedSearch }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct OverpassMember: Decodable {
    var role: String
    var geometry: [OverpassCoordinate]?
}

private struct OverpassCoordinate: Decodable {
    var lat: Double
    var lon: Double
}

private struct NominatimBoundary {
    var latitude: Double
    var longitude: Double
    var names: [String]
    var displayName: String
    var className: String
    var type: String
    var addressType: String
    var boundingBox: [Double]
    var rings: [(points: [GeoCoordinate], isHole: Bool)]?

    var center: GeoCoordinate { GeoCoordinate(latitude: latitude, longitude: longitude) }

    var isAdministrative: Bool {
        (className == "boundary" && type == "administrative") ||
        ["city", "county", "state", "country", "region", "province", "municipality", "suburb", "district"]
            .contains(addressType.lowercased())
    }

    init?(json: [String: Any]) {
        guard let latitude = Self.number(json["lat"]),
              let longitude = Self.number(json["lon"]) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        displayName = json["display_name"] as? String ?? ""
        className = json["class"] as? String ?? ""
        type = json["type"] as? String ?? ""
        addressType = json["addresstype"] as? String ?? ""
        boundingBox = (json["boundingbox"] as? [String] ?? []).compactMap(Double.init)

        var aliases: [String] = []
        if let name = json["name"] as? String { aliases.append(name) }
        if let names = json["namedetails"] as? [String: String] {
            aliases.append(contentsOf: names.filter { key, _ in
                key == "name" || key == "alt_name" || key == "official_name" ||
                key.hasPrefix("name:") || key.hasPrefix("alt_name:") || key.hasPrefix("official_name:")
            }.values)
        }
        names = aliases

        if let geometry = json["geojson"] as? [String: Any] {
            rings = Self.rings(from: geometry)
        } else {
            rings = nil
        }
    }

    func matches(_ searchName: String) -> Bool {
        let expected = Self.normalized(searchName)
        guard !expected.isEmpty else { return false }
        let candidates = names + [displayName.components(separatedBy: ",").first ?? ""]
        return candidates
            .flatMap { $0.split(separator: ";").map(String.init) }
            .contains { Self.normalized($0) == expected }
    }

    func contains(_ coordinate: GeoCoordinate) -> Bool {
        guard boundingBox.count == 4 else { return false }
        let south = boundingBox[0]
        let north = boundingBox[1]
        let west = boundingBox[2]
        let east = boundingBox[3]
        return coordinate.latitude >= south && coordinate.latitude <= north &&
            coordinate.longitude >= west && coordinate.longitude <= east
    }

    private static func rings(from geometry: [String: Any]) -> [(points: [GeoCoordinate], isHole: Bool)]? {
        let type = geometry["type"] as? String
        let coordinates = geometry["coordinates"] as? [Any]
        let polygons: [[Any]]
        switch type {
        case "Polygon":
            guard let coordinates else { return nil }
            polygons = [coordinates]
        case "MultiPolygon":
            guard let coordinates else { return nil }
            polygons = coordinates.compactMap { $0 as? [Any] }
        default:
            return nil
        }

        var result: [(points: [GeoCoordinate], isHole: Bool)] = []
        for polygon in polygons {
            for (ringIndex, rawRing) in polygon.enumerated() {
                guard let positions = rawRing as? [Any] else { continue }
                let points = positions.compactMap { rawPosition -> GeoCoordinate? in
                    guard let position = rawPosition as? [NSNumber], position.count >= 2 else { return nil }
                    let longitude = position[0].doubleValue
                    let latitude = position[1].doubleValue
                    guard longitude.isFinite, latitude.isFinite,
                          (-180...180).contains(longitude), (-90...90).contains(latitude) else { return nil }
                    return GeoCoordinate(latitude: latitude, longitude: longitude)
                }
                if points.count >= 3 {
                    result.append((points: points, isHole: ringIndex > 0))
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Sequence where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
