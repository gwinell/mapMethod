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
        request.resultTypes = [.address]
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

    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    private let cacheURL: URL
    private var cache: [String: MapOutline]
    private let session = URLSession(configuration: .ephemeral)

    private init() {
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
        let key = "\(normalizedName)|\(place.coordinate.latitude.rounded(toPlaces: 2))|\(place.coordinate.longitude.rounded(toPlaces: 2))"
        if let saved = cache[key] { return saved }

        let escapedName = NSRegularExpression.escapedPattern(for: place.name)
        let searchQuery = """
        [out:json][timeout:20];
        relation["boundary"="administrative"]["name"~"^\(escapedName)$",i];
        out center 30;
        """
        let candidates = try await request(searchQuery).elements.filter { $0.type == "relation" }
        guard let selected = candidates.min(by: { distance($0.center, to: place.coordinate) < distance($1.center, to: place.coordinate) }) else {
            throw BoundaryLookupError.noBoundary(place.name)
        }

        // Public Overpass instances are shared community infrastructure. Keep lookups user-triggered and spaced.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let geometryQuery = """
        [out:json][timeout:25];
        relation(\(selected.id));
        out geom;
        """
        let response = try await request(geometryQuery)
        guard let relation = response.elements.first(where: { $0.id == selected.id }) else {
            throw BoundaryLookupError.noBoundary(place.name)
        }

        let rings = Self.rings(from: relation.members ?? [])
        guard let outline = MapOutline.fromGeographicRings(rings, name: place.name), outline.area > 0 else {
            throw BoundaryLookupError.invalidGeometry(place.name)
        }
        cache[key] = outline
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        return outline
    }

    private func request(_ query: String) async throws -> OverpassResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("MapMethod/0.1.0 (https://github.com/gwinell/mapMethod)", forHTTPHeaderField: "User-Agent")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BoundaryLookupError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw BoundaryLookupError.server(response.statusCode) }
        do {
            return try JSONDecoder().decode(OverpassResponse.self, from: data)
        } catch {
            throw BoundaryLookupError.invalidResponse
        }
    }

    private func distance(_ center: OverpassCoordinate?, to coordinate: GeoCoordinate) -> Double {
        guard let center else { return .greatestFiniteMagnitude }
        let latitudeDelta = center.lat - coordinate.latitude
        let longitudeDelta = (center.lon - coordinate.longitude) * cos(coordinate.latitude * .pi / 180)
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

    var errorDescription: String? {
        switch self {
        case .noBoundary(let name): return "Для «\(name)» не найден административный контур. Попробуйте нарисовать его вручную."
        case .invalidGeometry(let name): return "Контур «\(name)» не удалось обработать. Можно нарисовать его вручную."
        case .invalidResponse: return "Сервис границ прислал некорректный ответ. Попробуйте позже."
        case .server(let status): return "Сервис границ временно недоступен (\(status)). Попробуйте позже."
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
}

private struct OverpassMember: Decodable {
    var role: String
    var geometry: [OverpassCoordinate]?
}

private struct OverpassCoordinate: Decodable {
    var lat: Double
    var lon: Double
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
