import Foundation

public enum Kind: String, Codable, Hashable, CaseIterable, Sendable {
    case tv, radio

    public var faroese: String { self == .tv ? "Sjónvarp" : "Útvarp" }
}

// MARK: - Live channels

/// KVF live streams. Both TV and radio are HLS from play.kringvarp.fo; the
/// /redirect endpoint resolves to the current edge server, so it stays valid
/// even when the CDN host rotates.
public struct Channel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let kind: Kind
    public let url: URL
}

public let channels: [Channel] = [
    Channel(
        id: "sjonvarp", name: "KVF Sjónvarp", tagline: "Beinleiðis sjónvarp", kind: .tv,
        url: URL(string: "https://play.kringvarp.fo/redirect/kvf/_definst_/smil:kvf.smil?type=m3u8")!),
    Channel(
        id: "tingvarp", name: "Tingvarp", tagline: "Løgtingið beinleiðis", kind: .tv,
        url: URL(string: "https://play.kringvarp.fo/redirect/tingvarp/_definst_/smil:tingvarp.smil?type=m3u8")!),
    Channel(
        id: "utvarp", name: "Útvarp Føroya", tagline: "Beinleiðis útvarp", kind: .radio,
        url: URL(string: "https://play.kringvarp.fo/redirect/radio/_definst_/radio.stream?type=m3u8")!),
    Channel(
        id: "tingutvarp", name: "Tingútvarp", tagline: "Útvarp úr Løgtinginum", kind: .radio,
        url: URL(string: "https://play.kringvarp.fo/redirect/tingradio/_definst_/tingradio.stream?type=m3u8")!),
]

public let defaultChannelID = "sjonvarp"

public func channel(_ id: String) -> Channel? { channels.first { $0.id == id } }

// MARK: - On demand

public struct Show: Identifiable, Hashable, Codable, Sendable {
    public let feedID: String
    public let title: String
    public let kind: Kind

    public var id: String { "\(kind.rawValue):\(feedID)" }

    public init(feedID: String, title: String, kind: Kind) {
        self.feedID = feedID
        self.title = title
        self.kind = kind
    }
}

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let date: Date?
    public let durationSec: Int
    public let description: String
    public let mediaURL: URL
    public let kind: Kind
}

public struct ShowEpisodes: Hashable, Codable, Sendable {
    public let feedID: String
    public let title: String
    public let image: URL?
    public let kind: Kind
    public let episodes: [Episode]
}

// MARK: - Programme guide (Skrá)

public struct GuideEntry: Identifiable, Hashable, Sendable {
    public let id = UUID()
    /// "HH:MM"
    public let time: String
    public let title: String
    public let subtitle: String
    public let description: String
    public let image: URL?
    /// Faroe-only viewing/listening restriction.
    public let restricted: Bool

    /// Only rows with something to read are worth expanding. Plenty of entries carry
    /// a generic programme banner and no description; those used to open into nothing
    /// but a large picture.
    public var hasDetail: Bool { !description.isEmpty }
}

public struct GuideDay: Sendable {
    public let kind: Kind
    public let date: String
    public let entries: [GuideEntry]

    public init(kind: Kind, date: String, entries: [GuideEntry]) {
        self.kind = kind
        self.date = date
        self.entries = entries
    }

    /// The programme on air, worked out from the clock.
    ///
    /// kvf.fo marks the current programme in the page itself, but that marker is
    /// baked in when the page is rendered and we cache pages for 15 minutes, so it
    /// drifts — and KVF's own copy is often already behind. Nil unless this is
    /// today's schedule, or when the day has not started yet.
    public func onAir(now: Date = Date()) -> GuideEntry.ID? {
        guard date == todayDateString(now) else { return nil }

        let minutesNow = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)

        // Radio days run past midnight — 23:00 is followed by 00:00, which belongs to
        // tomorrow. Carry a day's offset from the wrap so those entries sort last
        // instead of matching every time of day.
        var offset = 0
        var previous = -1
        var onAir: GuideEntry.ID?

        for entry in entries {
            guard let start = minutesSinceMidnight(entry.time) else { continue }
            if start < previous { offset += 24 * 60 }
            previous = start

            if start + offset <= minutesNow { onAir = entry.id } else { break }
        }

        return onAir
    }
}

private func minutesSinceMidnight(_ time: String) -> Int? {
    let parts = time.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
    return hour * 60 + minute
}

// MARK: - VIT (children's section)

public struct VitShow: Identifiable, Hashable, Codable, Sendable {
    /// Path on kvf.fo, e.g. "/vit/sending/sv/snipp-snapp".
    public let path: String
    public let title: String
    public let image: URL?

    public var id: String { path }

    public init(path: String, title: String, image: URL? = nil) {
        self.path = path
        self.title = title
        self.image = image
    }

    // Identity is the path alone. Favourites are stored as JSON, and artwork added
    // later (or a retitled programme) would otherwise stop matching what is starred.
    public static func == (lhs: VitShow, rhs: VitShow) -> Bool { lhs.path == rhs.path }

    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

public struct VitEpisode: Identifiable, Hashable, Sendable {
    /// kvf.fo's programme id, used as ?sid= on the show page. Empty when the show
    /// page carries a single programme and no episode list.
    public let sid: String
    public let title: String
    public let date: Date?
    public let image: URL?

    public var id: String { sid.isEmpty ? title : sid }

    public init(sid: String, title: String, date: Date?, image: URL?) {
        self.sid = sid
        self.title = title
        self.date = date
        self.image = image
    }
}

public struct VitShowDetail: Sendable {
    public let show: VitShow
    public let episodes: [VitEpisode]
}

/// VIT pages have no podcast feed; the stream is assembled from the JW Player
/// variables the page sets. See `parseVitStream`.
public struct VitStream: Hashable, Sendable {
    public let url: URL
    public let video: Bool
}
