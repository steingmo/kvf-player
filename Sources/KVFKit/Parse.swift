import Foundation

// Pure parsers for the HTML/XML kvf.fo serves. Kept free of networking so
// `swift run kvf-check` can exercise them against fixtures.

// ponytail: patterns are compile-time literals — a bad one is a crash on first use, not a runtime branch.
private func rx(_ pattern: String, ignoreCase: Bool = false) -> Regex<AnyRegexOutput> {
    let re = try! Regex(pattern).dotMatchesNewlines()
    return ignoreCase ? re.ignoresCase() : re
}

private func group(_ re: Regex<AnyRegexOutput>, _ text: some StringProtocol, _ n: Int = 1) -> String? {
    guard let match = try? re.firstMatch(in: String(text)), let value = match[n].substring else { return nil }
    return String(value)
}

// MARK: - HTML text

private let tagRE = rx("<[^>]*>")
private let whitespaceRE = rx("\\s+")
private let entities = [
    ("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&apos;", "'"),
    ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"),
]

public func stripTags(_ html: some StringProtocol) -> String {
    var text = String(html).replacing(tagRE, with: "")
    for (entity, replacement) in entities {
        text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text.replacing(whitespaceRE, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

public struct Anchor: Sendable {
    public let href: String
    public let text: String
}

private let anchorRE = rx("<a\\b[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>", ignoreCase: true)

public func extractAnchors(_ html: String) -> [Anchor] {
    html.matches(of: anchorRE).compactMap { match in
        guard let href = match[1].substring, let inner = match[2].substring else { return nil }
        return Anchor(href: String(href), text: stripTags(inner))
    }
}

// MARK: - On-demand catalogue

private func normalizeTitle(_ title: String) -> String {
    title.lowercased().replacing(whitespaceRE, with: " ").trimmingCharacters(in: .whitespaces)
}

private let feedRE = rx("/podcast/(\\d+)/feed\\.xml")
private let sendingRE = rx("/(sjon|ljod)/sending/")

/// Map normalized show title → kind, from the /sjon and /ljod index pages.
public func kinds(inIndex html: String, kind: Kind) -> [String: Kind] {
    let marker = kind == .tv ? "/sjon/sending/" : "/ljod/sending/"
    var result: [String: Kind] = [:]
    for anchor in extractAnchors(html) where anchor.href.contains(marker) && !anchor.text.isEmpty {
        result[normalizeTitle(anchor.text)] = kind
    }
    return result
}

public func buildCatalogue(hubHTML: String, kindByTitle: [String: Kind]) -> [Show] {
    let anchors = extractAnchors(hubHTML)
    var shows: [String: Show] = [:]  // feedID → Show
    var order: [String] = []

    for index in anchors.indices {
        guard let feedID = group(feedRE, anchors[index].href), shows[feedID] == nil else { continue }

        // Nearest preceding anchor that names the show. Prefer a /sjon|/ljod/sending
        // link (it also tells us the kind); fall back to the closest readable text.
        var title = ""
        var kind: Kind?
        var candidateIndex = index
        while candidateIndex >= 0, candidateIndex >= index - 6 {
            let candidate = anchors[candidateIndex]
            if let section = group(sendingRE, candidate.href), !candidate.text.isEmpty {
                title = candidate.text
                kind = section == "sjon" ? .tv : .radio
                break
            }
            if title.isEmpty, !candidate.text.isEmpty, !candidate.href.contains("/podcast/") {
                title = candidate.text
            }
            candidateIndex -= 1
        }

        if title.isEmpty { title = anchors[index].text }
        if kind == nil { kind = kindByTitle[normalizeTitle(title)] }
        guard !title.isEmpty, let kind else { continue }

        shows[feedID] = Show(feedID: feedID, title: title, kind: kind)
        order.append(feedID)
    }

    return order.compactMap { shows[$0] }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

// MARK: - Podcast feed

private let sidRE = rx("sid=(\\d+)")
private let longDigitsRE = rx("(\\d{4,})")
private let mediaFileRE = rx("/([^/]+)\\.(?:mp4|m4a|m4v|mp3|aac)(?:\\?|$)", ignoreCase: true)
private let videoTypeRE = rx("video", ignoreCase: true)
private let videoExtRE = rx("\\.mp4|\\.m4v", ignoreCase: true)
private let allDigitsRE = rx("^\\d+$")

private let pubDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter
}()

/// SAX rather than the tree API: XMLDocument is macOS-only, and this has to compile
/// for tvOS too. Collects the handful of channel and item fields the app uses.
private final class FeedCollector: NSObject, XMLParserDelegate {
    private(set) var channel: [String: String] = [:]
    private(set) var items: [[String: String]] = []
    /// Any well-formed XML parses; only a feed has <channel>.
    private(set) var sawChannel = false

    private var current: [String: String] = [:]
    private var text = ""
    private var depth = 0
    private var inItem = false
    private var inChannelImage = false

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String]
    ) {
        depth += 1
        text = ""

        switch element {
        case "channel":
            sawChannel = true
        case "item":
            inItem = true
            current = [:]
        case "image" where !inItem:
            inChannelImage = true
        case "itunes:image" where !inItem:
            // An empty element — the URL is an attribute, so take it here.
            if let href = attributes["href"] { channel["itunes:image"] = href }
        case "enclosure" where inItem:
            current["enclosure.url"] = attributes["url"] ?? ""
            current["enclosure.type"] = attributes["type"] ?? ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
        qualifiedName: String?
    ) {
        defer {
            depth -= 1
            text = ""
        }

        switch element {
        case "item":
            items.append(current)
            inItem = false
        case "image":
            inChannelImage = false
        default:
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            if inItem {
                // Keep the first occurrence: <item> wins over anything nested deeper.
                if current[element] == nil { current[element] = value }
            } else if inChannelImage {
                if element == "url" { channel["image.url"] = value }
            } else if channel[element] == nil {
                channel[element] = value
            }
        }
    }
}

func parseDurationSec(_ raw: String?) -> Int {
    guard let text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return 0 }
    if (try? allDigitsRE.firstMatch(in: text)) != nil, let seconds = Int(text) { return seconds }
    let parts = text.split(separator: ":").map { Int($0) }
    guard !parts.contains(nil) else { return 0 }
    return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
}

func episodeID(guid: String?, mediaURL: String, index: Int) -> String {
    let source = guid ?? ""
    if let sid = group(sidRE, source) ?? group(longDigitsRE, source) { return sid }
    if let file = group(mediaFileRE, mediaURL) { return file }
    return String(index)
}

public enum FeedError: LocalizedError {
    case noChannel(String)
    case invalidFeedID(String)
    case layoutChanged(String)

    public var errorDescription: String? {
        switch self {
        case .noChannel(let id): "Sendingin \(id) hevur ikki nakað <rss><channel>."
        case .invalidFeedID(let id): "Ógyldugt feed-id: \(id)"
        case .layoutChanged(let what): "Kundi ikki lesa \(what) — kvf.fo hevur broytt uppsetingina."
        }
    }
}

public func parseFeed(feedID: String, xml data: Data) throws -> ShowEpisodes {
    let parser = XMLParser(data: data)
    let collector = FeedCollector()
    parser.delegate = collector
    guard parser.parse(), collector.sawChannel else {
        throw FeedError.noChannel(feedID)
    }

    let imageString = collector.channel["itunes:image"] ?? collector.channel["image.url"] ?? ""
    let title = stripTags(collector.channel["title"] ?? "Sending")

    var episodes: [Episode] = []
    var showKind: Kind = .radio

    for (index, item) in collector.items.enumerated() {
        guard let mediaString = item["enclosure.url"], !mediaString.isEmpty,
              let mediaURL = URL(string: mediaString)
        else { continue }

        let mediaType = item["enclosure.type"] ?? ""
        let isVideo = (try? videoTypeRE.firstMatch(in: mediaType)) != nil
            || (try? videoExtRE.firstMatch(in: mediaString)) != nil
        let kind: Kind = isVideo ? .tv : .radio
        showKind = kind

        let rawDescription = item["description"] ?? item["itunes:summary"] ?? ""

        episodes.append(
            Episode(
                id: episodeID(guid: item["guid"], mediaURL: mediaString, index: index),
                title: stripTags(item["title"] ?? "Uttan heiti"),
                date: item["pubDate"].flatMap { pubDateFormatter.date(from: $0) },
                durationSec: parseDurationSec(item["itunes:duration"]),
                description: stripTags(rawDescription),
                mediaURL: mediaURL,
                kind: kind))
    }

    return ShowEpisodes(
        feedID: feedID, title: title, image: kvfImageURL(imageString), kind: showKind, episodes: episodes)
}

// MARK: - Programme guide

private let normalRE = rx("<div class=\"s-normal([^\"]*)\">\\s*(\\d{2}:\\d{2})")
private let heitiRE = rx("<div class=\"s-heiti\">(.*?)</div>")
private let subtitleRE = rx("<div class=\"s-subtitle\">(.*?)</div>")
private let textRE = rx("<div class=\"s-text\">(.*?)</div>")
private let imageRE = rx("<div class=\"s-imgmedia\">.*?src=\"([^\"]+)\"")
private let leadingDashRE = rx("^-\\s*")

public func parseGuideHTML(_ html: String) -> [GuideEntry] {
    html.components(separatedBy: "<div class=\"views-row").dropFirst().compactMap { row in
        guard let match = try? normalRE.firstMatch(in: row),
              let classes = match[1].substring, let time = match[2].substring
        else { return nil }

        let title = group(heitiRE, row).map(stripTags) ?? ""
        guard !title.isEmpty else { return nil }

        let subtitle = group(subtitleRE, row)
            .map { stripTags($0).replacing(leadingDashRE, with: "") } ?? ""

        return GuideEntry(
            time: String(time),
            title: title,
            subtitle: subtitle,
            description: group(textRE, row).map(stripTags) ?? "",
            image: group(imageRE, row).flatMap { kvfImageURL($0) },
            restricted: row.contains("class=\"image-container\""),
            current: classes.contains("s-current"))
    }
}

public func resolveKVFURL(_ source: String) -> URL? {
    URL(string: source.hasPrefix("http") ? source : "https://kvf.fo\(source)")
}

private let styleDerivativeRE = rx("/styles/[^/]+/public/")

/// kvf.fo serves Drupal image *derivatives*: the "podcast" style crops a show's
/// 16:9 banner to a square — cutting the title off both ends — and the guide style
/// shrinks thumbnails to 116x65. Dropping the style segment gives the original.
/// kvf.fo's "news_xtra_xtra_large" derivative: a uniform 648x364 at well under a
/// quarter megabyte. The originals behind these thumbnails run to 4727x1980 and
/// several megabytes — decoding a gridful of those exhausts an Apple TV's memory
/// and some tiles silently come back blank.
public func kvfThumbnailURL(_ source: String) -> URL? {
    guard !source.isEmpty else { return nil }

    let restyled = source.replacing(styleDerivativeRE, with: "/styles/news_xtra_xtra_large/public/")
    guard restyled != source else { return resolveKVFURL(source) }

    // The itok token signs one specific derivative; kvf.fo serves the others without it.
    return resolveKVFURL(restyled.split(separator: "?").first.map(String.init) ?? restyled)
}

public func kvfImageURL(_ source: String) -> URL? {
    guard !source.isEmpty else { return nil }

    let stripped = source.replacing(styleDerivativeRE, with: "/")
    guard stripped != source else { return resolveKVFURL(source) }

    // The ?itok= token only signs the derivative; the original needs no query.
    let path = stripped.split(separator: "?").first.map(String.init) ?? stripped
    return resolveKVFURL(path)
}

// MARK: - VIT

private let vitMediaRE = rx("var\\s+media\\s*=\\s*'([^']+)'")
private let vitModeRE = rx("var\\s+mode\\s*=\\s*'([^']+)'")
private let vitSidRE = rx("[?&]sid=(\\d+)")
private let vitTitleFieldRE = rx("views-field-title.*?<a[^>]*>(.*?)</a>")
private let vitDateRE = rx("content=\"(\\d{4}-\\d{2}-\\d{2}T[^\"]*)\"")
private let vitImageRE = rx("<img[^>]*src=\"([^\"]+)\"")
private let pageTitleRE = rx("<title>(.*?)</title>")

private let isoFormatter = ISO8601DateFormatter()

/// VIT programmes have no podcast feed. The page sets JW Player variables and the
/// site's own jwplayer_on_demand.js assembles the stream URL from them; this builds
/// the same URL so the app can play it natively instead of embedding a web player.
public func parseVitStream(_ html: String) -> VitStream? {
    guard let media = group(vitMediaRE, html), let mode = group(vitModeRE, html),
          mode == "video" || mode == "audio",
          let url = URL(
            string: "https://vod.kringvarp.fo/redirect/\(mode)/_definst_/smil:smil/\(mode)/\(media).smil?type=m3u8")
    else { return nil }

    return VitStream(url: url, video: mode == "video")
}

/// "Alt um djór | Kringvarp Føroya" -> "Alt um djór"
public func parseVitPageTitle(_ html: String) -> String {
    guard let raw = group(pageTitleRE, html) else { return "" }
    return stripTags(raw.split(separator: "|").first.map(String.init) ?? raw)
}

public func parseVitEpisodes(_ html: String) -> [VitEpisode] {
    var seen = Set<String>()
    var episodes: [VitEpisode] = []

    for group_ in html.components(separatedBy: "quicktabs-views-group").dropFirst() {
        guard let sid = group(vitSidRE, group_),
              let rawTitle = group(vitTitleFieldRE, group_)
        else { continue }

        let title = stripTags(rawTitle)
        guard !title.isEmpty, seen.insert(sid).inserted else { continue }

        episodes.append(
            VitEpisode(
                sid: sid,
                title: title,
                date: group(vitDateRE, group_).flatMap { isoFormatter.date(from: $0) },
                image: group(vitImageRE, group_).flatMap { kvfImageURL($0) }))
    }

    return episodes
}

private let vitPathRE = rx("href=\"(/vit/sending/[^\"]+)\"")
private let vitRowImageRE = rx("<img[^>]*src=\"([^\"]+)\"")
private let vitRowTitleRE = rx("views-field-title[^\"]*\".*?<a[^>]*>(.*?)</a>")

public func parseVitShows(_ html: String) -> [VitShow] {
    var shows: [String: VitShow] = [:]
    var order: [String] = []

    // Each programme sits in a swiper-row carrying its thumbnail and title. A
    // programme can appear in several carousels, so prefer the block that has art.
    for row in html.components(separatedBy: "class=\"swiper-row\"").dropFirst() {
        guard let path = group(vitPathRE, row) else { continue }

        let title = group(vitRowTitleRE, row).map(stripTags) ?? ""
        let image = group(vitRowImageRE, row).flatMap { kvfThumbnailURL($0) }

        if let existing = shows[path] {
            if existing.image == nil, image != nil {
                shows[path] = VitShow(path: path, title: existing.title, image: image)
            }
            continue
        }
        guard !title.isEmpty else { continue }

        shows[path] = VitShow(path: path, title: title, image: image)
        order.append(path)
    }

    // Fall back to plain anchors if the carousel markup ever goes away.
    if shows.isEmpty {
        for anchor in extractAnchors(html)
        where anchor.href.hasPrefix("/vit/sending/") && !anchor.text.isEmpty {
            if shows[anchor.href] == nil {
                shows[anchor.href] = VitShow(path: anchor.href, title: anchor.text)
                order.append(anchor.href)
            }
        }
    }

    return order.compactMap { shows[$0] }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}
