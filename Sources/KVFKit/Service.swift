import Foundation
import OSLog

private let log = Logger(subsystem: "com.steingrimosa.kvf", category: "kvf")

private let base = "https://kvf.fo"

public enum HTTPError: LocalizedError {
    case status(url: URL, code: Int)

    public var errorDescription: String? {
        switch self {
        case .status(let url, let code): "\(url.host() ?? "kvf.fo") svaraði \(code)."
        }
    }
}

/// Fetches and parses everything the app needs from kvf.fo, with the same TTLs
/// the Glaze backend used: 6h for the catalogues, 15 min for the live schedule.
public actor KVFService {
    public static let shared = KVFService()

    private struct Cached<Value> {
        let value: Value
        let fetchedAt: Date

        func valid(for ttl: TimeInterval) -> Bool { Date().timeIntervalSince(fetchedAt) < ttl }
    }

    private static let catalogueTTL: TimeInterval = 6 * 60 * 60
    private static let episodesTTL: TimeInterval = 10 * 60
    private static let guideTTL: TimeInterval = 15 * 60  // a live schedule drifts as programmes run over/under

    private var catalogueCache: Cached<[Show]>?
    private var vitCache: Cached<[VitShow]>?
    private var episodesCache: [String: Cached<ShowEpisodes>] = [:]
    private var guideCache: [String: Cached<GuideDay>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            // Some CDN edges reject a default agent string.
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml,*/*",
        ]
        return URLSession(configuration: config)
    }()

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(url: url, code: http.statusCode)
        }
        return data
    }

    private func fetchText(_ path: String) async throws -> String {
        guard let url = URL(string: path) else { throw FeedError.layoutChanged(path) }
        let data = try await fetchData(url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: On-demand catalogue

    public func catalogue(force: Bool = false) async throws -> [Show] {
        if !force, let cached = catalogueCache, cached.valid(for: Self.catalogueTTL) { return cached.value }

        async let hub = fetchText("\(base)/podcast")
        async let tv = try? fetchText("\(base)/sjon")
        async let radio = try? fetchText("\(base)/ljod")

        var kindByTitle: [String: Kind] = [:]
        if let html = await tv { kindByTitle.merge(kinds(inIndex: html, kind: .tv)) { _, new in new } }
        if let html = await radio { kindByTitle.merge(kinds(inIndex: html, kind: .radio)) { _, new in new } }

        let shows = buildCatalogue(hubHTML: try await hub, kindByTitle: kindByTitle)
        guard !shows.isEmpty else { throw FeedError.layoutChanged("sendingarskránni") }

        catalogueCache = Cached(value: shows, fetchedAt: Date())
        log.info("Parsed \(shows.count) on-demand shows")
        return shows
    }

    public func episodes(feedID: String) async throws -> ShowEpisodes {
        guard feedID.allSatisfy(\.isNumber), !feedID.isEmpty else { throw FeedError.invalidFeedID(feedID) }
        if let cached = episodesCache[feedID], cached.valid(for: Self.episodesTTL) { return cached.value }

        guard let url = URL(string: "\(base)/podcast/\(feedID)/feed.xml") else {
            throw FeedError.invalidFeedID(feedID)
        }
        let show = try parseFeed(feedID: feedID, xml: try await fetchData(url))
        episodesCache[feedID] = Cached(value: show, fetchedAt: Date())
        return show
    }

    // MARK: Programme guide

    public func guideDay(kind: Kind, date: String, force: Bool = false) async throws -> GuideDay {
        let key = "\(kind.rawValue):\(date)"
        if !force, let cached = guideCache[key], cached.valid(for: Self.guideTTL) { return cached.value }

        let path = kind == .tv ? "sv" : "uv"
        let entries = parseGuideHTML(try await fetchText("\(base)/nskra/\(path)?date=\(date)"))
        guard !entries.isEmpty else { throw FeedError.layoutChanged("skránni") }

        let day = GuideDay(kind: kind, date: date, entries: entries)
        guideCache[key] = Cached(value: day, fetchedAt: Date())
        return day
    }

    // MARK: VIT

    public func vitShows(force: Bool = false) async throws -> [VitShow] {
        if !force, let cached = vitCache, cached.valid(for: Self.catalogueTTL) { return cached.value }

        let shows = parseVitShows(try await fetchText("\(base)/sjon/vit"))
        guard !shows.isEmpty else { throw FeedError.layoutChanged("VIT-skránni") }

        vitCache = Cached(value: shows, fetchedAt: Date())
        return shows
    }
}
