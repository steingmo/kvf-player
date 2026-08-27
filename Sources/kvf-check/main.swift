// Smallest thing that fails if the kvf.fo parsers break: fixtures in, asserts out.
// Run with `swift run kvf-check`. No network, no framework.

import Foundation
import KVFKit

var failures = 0

func check(_ label: String, _ passed: Bool) {
    print("\(passed ? "ok  " : "FAIL") \(label)")
    if !passed { failures += 1 }
}

// MARK: stripTags

check("stripTags strips markup and entities", stripTags("<b>Dagur &amp;  Vika</b>\n") == "Dagur & Vika")

// MARK: guide

let guideHTML = """
<div class="views-row"><div class="s-normal s-current">20:00
  <div class="s-heiti">Dagur &amp; Vika</div>
  <div class="s-subtitle">- tíðindaskrá</div>
  <div class="s-text">Tíðindi úr Føroyum.</div>
  <div class="s-imgmedia"><img src="/sites/dagur.jpg"></div>
  <div class="image-container"></div>
</div></div>
<div class="views-row"><div class="s-normal">21:00
  <div class="s-heiti">Kvøldsetningur</div>
</div></div>
"""

let guide = parseGuideHTML(guideHTML)
check("guide parses every row", guide.count == 2)
check("guide reads time and title", guide.first?.time == "20:00" && guide.first?.title == "Dagur & Vika")
check("guide strips the subtitle dash", guide.first?.subtitle == "tíðindaskrá")
check("guide flags the current programme", guide.first?.current == true && guide.last?.current == false)
check("guide flags Faroe-only entries", guide.first?.restricted == true && guide.last?.restricted == false)
check("guide resolves relative images", guide.first?.image?.absoluteString == "https://kvf.fo/sites/dagur.jpg")
check("guide knows which rows expand", guide.first?.hasDetail == true && guide.last?.hasDetail == false)

// Real schedules carry rows with a programme banner and no description; expanding
// those showed nothing but a large picture.
let imageOnlyHTML = """
<div class="views-row"><div class="s-normal">19:00
  <div class="s-heiti">Dagur og vika</div>
  <div class="s-imgmedia"><img src="/sites/default/files/styles/nvf-very-small/public/dv.png?itok=x"></div>
</div></div>
"""
let imageOnly = parseGuideHTML(imageOnlyHTML)
check("guide still reads an image-only row", imageOnly.first?.image != nil)
check("guide will not expand a row with no description", imageOnly.first?.hasDetail == false)

// MARK: image URLs

check(
    "image URL drops the Drupal style segment and its itok token",
    kvfImageURL("https://kvf.fo/sites/default/files/styles/podcast/public/dv.png?itok=cRre1uY5")?
        .absoluteString == "https://kvf.fo/sites/default/files/dv.png")
check(
    "image URL keeps subdirectories under files/",
    kvfImageURL("/sites/default/files/styles/guide/public/2026-08/vedrid.jpg")?
        .absoluteString == "https://kvf.fo/sites/default/files/2026-08/vedrid.jpg")
check(
    "image URL leaves a non-derivative alone",
    kvfImageURL("https://kvf.fo/sites/default/files/dv.png")?
        .absoluteString == "https://kvf.fo/sites/default/files/dv.png")
check("image URL rejects an empty source", kvfImageURL("") == nil)

// MARK: catalogue

let hubHTML = """
<a href="/tiltak/whatever">Rás 2</a><a href="/podcast/789/feed.xml">RSS</a>
<a href="/sjon/sending/dagur-og-vika">Dagur og Vika</a><a href="/podcast/123/feed.xml">RSS</a>
<a href="/ljod/sending/morgunsending">Morgunsending</a><a href="/podcast/456/feed.xml">RSS</a>
<a href="/podcast/123/feed.xml">duplicate</a>
"""
let radioIndexHTML = #"<a href="/ljod/sending/ras-2">Rás 2</a>"#

let catalogue = buildCatalogue(hubHTML: hubHTML, kindByTitle: kinds(inIndex: radioIndexHTML, kind: .radio))
check("catalogue dedupes by feed id", catalogue.count == 3)
check("catalogue sorts by title", catalogue.map(\.title) == ["Dagur og Vika", "Morgunsending", "Rás 2"])
check("catalogue reads kind from the sending link", catalogue.first { $0.feedID == "123" }?.kind == .tv)
check("catalogue reads kind from the sending link (radio)", catalogue.first { $0.feedID == "456" }?.kind == .radio)
check("catalogue falls back to the index page for kind", catalogue.first { $0.feedID == "789" }?.kind == .radio)

// A /sjon|/ljod/sending link within 6 anchors wins over a closer plain-text
// title — it is the only thing that also states the kind.
let nearestHTML = #"<a href="/sjon/sending/x">Sending X</a><a href="/tiltak/y">Onnur tekst</a><a href="/podcast/5/feed.xml">RSS</a>"#
check(
    "catalogue prefers the nearest sending link over a closer plain title",
    buildCatalogue(hubHTML: nearestHTML, kindByTitle: [:]).map(\.title) == ["Sending X"])

let unnamed = buildCatalogue(hubHTML: #"<a href="/podcast/999/feed.xml">RSS</a>"#, kindByTitle: [:])
check("catalogue drops shows it cannot name or type", unnamed.isEmpty)

// MARK: VIT

let vitHTML = """
<a href="/vit/sending/sv/snipp-snapp">Snipp Snapp</a>
<a href="/vit/sending/sv/snipp-snapp">Snipp Snapp</a>
<a href="/vit/sending/sv/anna">Anna og Bertha</a>
<a href="/sjon/sending/ikki-vit">Ikki VIT</a>
"""
let vit = parseVitShows(vitHTML)
check("vit dedupes by path and ignores other sections", vit.count == 2)
check("vit sorts by title", vit.map(\.title) == ["Anna og Bertha", "Snipp Snapp"])

// MARK: VIT programme pages

let vitPageHTML = """
<title>Alt um djór | Kringvarp Føroya</title>
<script>
var media = 'BTA00375_UT304_Alt_um_djor_Kuluboeka_15_16012018';
var created = '2024';
var mode = 'video';
</script>
<div class="quicktabs-views-group">
  <div class="views-field views-field-field-mynd"><a href="/vit/sending/sv/alt-um-djor?sid=100105"><img src="/sites/default/files/styles/news_xtra_xtra_large/public/kuluboka.jpg?itok=UeDk24LH" /></a></div>
  <span class="views-field views-field-title"><span class="field-content"><a href="/vit/sending/sv/alt-um-djor?sid=100105">Kúlubøkan Klára</a></span></span>
  <div class="views-field views-field-field-publish"><span content="2022-01-18T12:00:00+00:00">18-01-2022</span></div>
</div><div class="quicktabs-views-group">
  <span class="views-field views-field-title"><span class="field-content"><a href="/vit/sending/sv/alt-um-djor?sid=131079">Fílurin Finnur</a></span></span>
  <div class="views-field views-field-field-publish"><span content="2021-11-09T12:00:00+00:00">09-11-2021</span></div>
</div>
"""

check(
    "vit stream is assembled from the page's player variables",
    parseVitStream(vitPageHTML)?.url.absoluteString
        == "https://vod.kringvarp.fo/redirect/video/_definst_/smil:smil/video/BTA00375_UT304_Alt_um_djor_Kuluboeka_15_16012018.smil?type=m3u8")
check("vit stream knows video from audio", parseVitStream(vitPageHTML)?.video == true)
check("vit stream is absent when the page sets no media", parseVitStream("<html></html>") == nil)
check("vit page title drops the site suffix", parseVitPageTitle(vitPageHTML) == "Alt um djór")

let vitEpisodes = parseVitEpisodes(vitPageHTML)
check("vit episodes parse", vitEpisodes.count == 2)
check("vit episodes read sid and title",
      vitEpisodes.first?.sid == "100105" && vitEpisodes.first?.title == "Kúlubøkan Klára")
check("vit episodes read the publish date", vitEpisodes.first?.date != nil)
check("vit episodes use the original image",
      vitEpisodes.first?.image?.absoluteString == "https://kvf.fo/sites/default/files/kuluboka.jpg")
check("vit episodes tolerate a missing image", vitEpisodes.last?.image == nil)

// Favourites persist as JSON, so both show types have to survive a round trip.
let storedShow = Show(feedID: "123", title: "Dagur og vika", kind: .tv)
let storedVit = VitShow(path: "/vit/sending/sv/alt-um-djor", title: "Alt um djór")
check(
    "a favourite show survives encode/decode",
    (try? JSONDecoder().decode([Show].self, from: JSONEncoder().encode([storedShow]))) == [storedShow])
check(
    "a favourite VIT show survives encode/decode",
    (try? JSONDecoder().decode([VitShow].self, from: JSONEncoder().encode([storedVit]))) == [storedVit])

// MARK: podcast feed

let feedXML = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Dagur &amp; Vika</title>
    <itunes:image href="https://kvf.fo/img.jpg"/>
    <item>
      <title>Dagur &amp; Vika 17.08.2026</title>
      <guid>https://kvf.fo/node/1?sid=98765</guid>
      <pubDate>Sun, 17 Aug 2026 19:00:00 +0000</pubDate>
      <itunes:duration>00:28:30</itunes:duration>
      <description>&lt;p&gt;Tíðindi   úr Føroyum&lt;/p&gt;</description>
      <enclosure url="https://vod.kringvarp.fo/x/dagur.mp4" type="video/mp4" length="1"/>
    </item>
    <item>
      <title>Uttan fjølmiðil</title>
    </item>
  </channel>
</rss>
"""

do {
    let show = try parseFeed(feedID: "123", xml: Data(feedXML.utf8))
    check("feed reads the channel title", show.title == "Dagur & Vika")
    check("feed reads the artwork", show.image?.absoluteString == "https://kvf.fo/img.jpg")
    check("feed skips items without an enclosure", show.episodes.count == 1)
    check("feed detects video as tv", show.kind == .tv && show.episodes.first?.kind == .tv)

    let episode = show.episodes[0]
    check("feed takes the episode id from sid", episode.id == "98765")
    check("feed parses HH:MM:SS durations", episode.durationSec == 1710)
    check("feed parses pubDate", episode.date != nil)
    check("feed strips markup from descriptions", episode.description == "Tíðindi úr Føroyum")
} catch {
    check("feed parses at all — \(error)", false)
}

do {
    _ = try parseFeed(feedID: "1", xml: Data("<html><body>nope</body></html>".utf8))
    check("feed rejects non-RSS", false)
} catch {
    check("feed rejects non-RSS", true)
}

// MARK: dates

check("addDays crosses month boundaries", addDays(1, to: "2026-08-31") == "2026-09-01")
check("addDays goes backwards", addDays(-1, to: "2026-01-01") == "2025-12-31")
check("formatGuideDate is Faroese", formatGuideDate("2026-08-18") == "týsdagur 18. august")
check("formatDuration shows hours only when needed", formatDuration(1710) == "28:30" && formatDuration(3661) == "1:01:01")
check("formatDuration hides unknown durations", formatDuration(0).isEmpty)

// `swift run kvf-check --live` also hits the real kvf.fo, to catch a layout
// change the fixtures can't see.
if CommandLine.arguments.contains("--live") {
    print("\nlive kvf.fo:")
    do {
        let shows = try await KVFService.shared.catalogue()
        check("catalogue has shows of both kinds",
              shows.contains { $0.kind == .tv } && shows.contains { $0.kind == .radio })
        print("     \(shows.count) shows")

        if let first = shows.first(where: { $0.kind == .tv }) {
            let detail = try await KVFService.shared.episodes(feedID: first.feedID)
            check("\(first.title) has episodes", !detail.episodes.isEmpty)
            print("     \(detail.episodes.count) episodes, first: \(detail.episodes.first?.title ?? "-")")

            // The artwork rewrite points off the feed's own URL, so prove it resolves.
            if let image = detail.image {
                let (bytes, response) = try await URLSession.shared.data(from: image)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                check("artwork original resolves (\(image.lastPathComponent))", code == 200 && bytes.count > 0)
                print("     \(bytes.count) bytes from \(image.absoluteString)")
            }
        }

        let day = try await KVFService.shared.guideDay(kind: .tv, date: todayDateString())
        check("today's TV guide parses", !day.entries.isEmpty)
        print("     \(day.entries.count) guide entries")

        let vit = try await KVFService.shared.vitShows()
        check("VIT list parses", !vit.isEmpty)
        print("     \(vit.count) VIT shows")

        // VIT has no feed: prove the assembled stream URL really resolves to a playlist.
        if let show = vit.first {
            let detail = try await KVFService.shared.vitShow(show)
            check("\(show.title) has VIT episodes", !detail.episodes.isEmpty)

            if let episode = detail.episodes.first {
                let stream = try await KVFService.shared.vitStream(path: show.path, sid: episode.sid)
                let (bytes, response) = try await URLSession.shared.data(from: stream.url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let playlist = String(decoding: bytes, as: UTF8.self)
                check(
                    "VIT stream resolves to an HLS playlist (\(episode.title))",
                    code == 200 && playlist.hasPrefix("#EXTM3U"))
                print("     \(detail.episodes.count) episodes, stream: \(stream.url.absoluteString)")
            }
        }
    } catch {
        check("live fetch — \(error.localizedDescription)", false)
    }
}

print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
