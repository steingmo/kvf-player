# KVF

A native macOS app for [Kringvarp Føroya](https://kvf.fo) — live TV, live radio,
the full on-demand catalogue, and the programme guide, in a real Mac app instead
of a browser tab.

- **Beinleiðis** — KVF Sjónvarp and Tingvarp (TV), Útvarp Føroya and Tingútvarp (radio)
- **Sendingar** — the whole on-demand catalogue (~690 programmes), searchable,
  with episode lists and a seekable player for both video and audio
- **Skrá** — day-by-day TV and radio schedules, with the current programme marked
- **VIT** — KVF's children's section
- **Uppáhald** — star any programme to pin it to the sidebar
- Picture-in-Picture, AirPlay, fullscreen, and Now Playing / media-key control

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask steingmo/tap/kvf-player
```

Or grab the latest notarized build from the
[Releases page](https://github.com/steingmo/kvf-player/releases), unzip, and drag
**KVF.app** to Applications. The app is signed and notarized with a Developer ID,
so it runs without Gatekeeper warnings.

Requires macOS 14 (Sonoma) or newer, Intel or Apple silicon.

The app checks for updates via [Sparkle](https://sparkle-project.org) (or on
demand from the KVF menu) and can install them in place. Homebrew installs can
also update with `brew upgrade --cask kvf-player`.

## Build

```sh
./build.sh          # release → build/KVF.app, ad-hoc signed
./build.sh debug    # faster build while developing
```

Requires the Xcode command line tools and nothing else — no package
dependencies. In Xcode, open `Package.swift`.

To cut a signed, notarized, universal build for distribution, see `release.sh`.

## Tests

```sh
swift run kvf-check          # parser checks against fixtures, offline
swift run kvf-check --live   # also hits kvf.fo, catches layout changes
```

## How it works

KVF publishes every on-demand programme as a standard podcast feed, so episodes
come from real feeds. Everything else — the catalogue index, the schedule, the
VIT list — is scraped from kvf.fo's HTML, because there's no API. Live TV and
radio are HLS from `play.kringvarp.fo`, played by AVPlayer.

Images need one extra step: kvf.fo serves Drupal image *derivatives*, and the
podcast style crops a show's 16:9 banner to a square — cutting the title off both
ends — while the guide style shrinks thumbnails to 116x65. `kvfImageURL` strips the
style segment to fetch the original instead.

`Sources/KVFKit/Parse.swift` is therefore the fragile part: it parses markup
that KVF can change at any time. When something stops showing up, run
`swift run kvf-check --live` to find out which parser broke.

Layout:

- `Sources/KVFKit/` — channels, models, scraping, podcast feeds, favourites. No UI.
- `Sources/KVF/` — SwiftUI app: `App.swift` (sidebar + routing), `Player.swift`,
  `Browse.swift` (Sendingar + VIT), `Guide.swift`.
- `Sources/kvf-check/` — the parser checks.

Notes for anyone reading the player code:

- One shared `AVPlayer` (`Playback.shared`), so two streams can never play at once.
  Volume and mute persist via KVO into UserDefaults.
- Player views refcount their appearances. SwiftUI builds the detail view twice at
  launch and discards the first copy; stopping playback on that stray `onDisappear`
  meant nothing played until you navigated away and back.
- What plays is driven by `onChange(of: url)`, not by view lifecycle. SwiftUI reuses
  the same `MediaView` when you switch channel, so no appear/disappear fires and
  keying playback to those left the previous stream running.
- `MediaView` keeps exactly **one** `PlayerHost`, in a fixed position in its `ZStack`,
  and only swaps the controls style between video and audio. AVKit supports a single
  presenting view per `AVPlayer`: two live `AVPlayerView`s tore down each other's
  video output, and sharing one view instance between two representables corrupted
  SwiftUI's layout tree (a hard crash). Don't add a second one.
- VIT programmes have no podcast feed. Their pages set JW Player variables and let
  kvf.fo's own script assemble the stream URL; `parseVitStream` builds the same URL,
  so VIT plays in the app's player like everything else. It costs one page fetch per
  episode, because the URL only exists on the episode's own page.

## Unofficial

This is an unofficial, independent client. It is not affiliated with, endorsed
by, or supported by Kringvarp Føroya. It plays the same public streams and feeds
that kvf.fo serves to any browser, and adds nothing and stores nothing on KVF's
side. Some programming is licensed for the Faroe Islands only and will not play
elsewhere — the app shows KVF's own restriction marker in the guide where it
applies.

Trademarks and all broadcast content belong to Kringvarp Føroya.

## Licence

MIT — see [LICENSE](LICENSE).
