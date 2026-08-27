import AVKit
import KVFKit
import MediaPlayer
import Observation
import SwiftUI

/// One AVPlayer for the whole app — switching channel or episode replaces the
/// item rather than stacking players, so two streams can never play at once.
/// Volume and mute ride along on the player and persist via KVO.
@Observable
@MainActor
final class Playback {
    static let shared = Playback()

    @ObservationIgnored let player = AVPlayer()

    var failure: String?
    var loading = false

    /// Mirrors of the player's volume and mute, so SwiftUI can bind to them.
    /// Writes go straight to the player; KVO brings back changes made from the
    /// player view's own controls or a media key.
    var volume: Float {
        get { volumeStore }
        set {
            volumeStore = newValue
            player.volume = newValue
        }
    }

    var isMuted: Bool {
        get { mutedStore }
        set {
            mutedStore = newValue
            player.isMuted = newValue
        }
    }

    private var volumeStore: Float = 1
    private var mutedStore = false

    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var nowPlaying = (title: "", subtitle: "", live: false)
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var settingObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        player.volume = defaults.object(forKey: "kvf.volume") as? Float ?? 1
        player.isMuted = defaults.bool(forKey: "kvf.muted")
        volumeStore = player.volume
        mutedStore = player.isMuted

        settingObservations = [
            player.observe(\.volume) { player, _ in
                UserDefaults.standard.set(player.volume, forKey: "kvf.volume")
                Task { @MainActor in Playback.shared.volumeStore = player.volume }
            },
            player.observe(\.isMuted) { player, _ in
                UserDefaults.standard.set(player.isMuted, forKey: "kvf.muted")
                Task { @MainActor in Playback.shared.mutedStore = player.isMuted }
            },
            // Keeps Now Playing in sync when the user pauses from AVPlayerView's
            // own controls rather than a media key.
            player.observe(\.timeControlStatus) { _, _ in
                Task { @MainActor in Playback.shared.publishNowPlaying() }
            },
        ]
        configureRemoteCommands()
    }

    /// Refcounts live player views. SwiftUI builds the detail view twice at launch
    /// and then tears the first copy down; stopping on that stray `onDisappear`
    /// used to kill playback before it started.
    func retain() {
        viewers += 1
    }

    func release() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { stop() }
    }

    /// Driven by `onChange(of: url)`, NOT by view lifecycle: SwiftUI reuses the same
    /// MediaView when you switch channel, so no appear/disappear event fires and
    /// keying playback to those left the previous stream playing.
    func play(_ url: URL, title: String, subtitle: String, live: Bool) {
        nowPlaying = (title, subtitle, live)
        guard currentURL != url else {
            player.play()
            return
        }
        load(url)
    }

    func retry() {
        guard let url = currentURL else { return }
        load(url)
    }

    private func load(_ url: URL) {
        currentURL = url
        failure = nil
        loading = true

        MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = !nowPlaying.live
        MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = !nowPlaying.live
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = !nowPlaying.live

        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status) { item, _ in
            Task { @MainActor in
                guard Playback.shared.currentURL == url else { return }
                switch item.status {
                case .readyToPlay:
                    Playback.shared.loading = false
                    Playback.shared.publishNowPlaying()
                case .failed:
                    Playback.shared.loading = false
                    Playback.shared.failure =
                        item.error?.localizedDescription
                        ?? "Streymurin er ikki tøkur. Kann vera bert í Føroyum ella ikki í send."
                default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        loading = false
        failure = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: Now Playing + media keys

    /// The app becomes the system's Now Playing app once it publishes metadata and
    /// claims the remote commands — that is also what routes the media keys here.
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in Self.onMain { $0.player.play() } }
        center.pauseCommand.addTarget { _ in Self.onMain { $0.player.pause() } }
        center.togglePlayPauseCommand.addTarget { _ in
            Self.onMain { $0.player.timeControlStatus == .paused ? $0.player.play() : $0.player.pause() }
        }
        // Pause rather than tear down, so the open view can resume from the same URL.
        center.stopCommand.addTarget { _ in Self.onMain { $0.player.pause() } }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            return Self.onMain { $0.seek(by: by) }
        }
        center.skipBackwardCommand.addTarget { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            return Self.onMain { $0.seek(by: -by) }
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            return Self.onMain { $0.seek(to: position) }
        }
    }

    /// Remote command handlers can arrive off the main thread; hop before touching
    /// the player, and answer the command centre right away.
    private static func onMain(_ body: @escaping @MainActor @Sendable (Playback) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in body(Playback.shared) }
        return .success
    }

    private func seek(by offset: TimeInterval) {
        seek(to: player.currentTime().seconds + offset)
    }

    private func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.publishNowPlaying() }
        }
    }

    fileprivate func publishNowPlaying() {
        guard currentURL != nil else { return }

        let elapsed = player.currentTime().seconds
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: nowPlaying.live,
            MPNowPlayingInfoPropertyPlaybackRate: Double(player.rate),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
        ]
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = Self.appArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = player.timeControlStatus == .paused ? .paused : .playing
    }

    // ponytail: the app icon is the only artwork we always have — live channels
    // publish no image, and the podcast feed's art is per-show, not per-episode.
    private static let appArtwork: MPMediaItemArtwork? = {
        guard let icon = NSApp.applicationIconImage else { return nil }
        return MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
    }()
}

// ponytail: AVPlayerView gives play/pause, scrubbing, volume, AirPlay, PiP and
// fullscreen for free — none of the Glaze app's custom control chrome is needed.
// AVKit supports a single presenting view per AVPlayer, so MediaView keeps exactly
// one of these in a fixed position and only swaps its controls style. Two live
// AVPlayerViews on one player tore down each other's video output; handing the same
// view instance to two representables instead corrupted SwiftUI's layout tree.
struct PlayerHost: NSViewRepresentable {
    var controlsStyle: AVPlayerViewControlsStyle = .floating

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = Playback.shared.player
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        apply(to: view)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        let player = Playback.shared.player
        if view.player !== player { view.player = player }
        apply(to: view)
    }

    private func apply(to view: AVPlayerView) {
        view.controlsStyle = controlsStyle
        view.showsFullScreenToggleButton = controlsStyle == .floating
    }
}

// MARK: - Screens

struct LiveView: View {
    let channel: Channel

    var body: some View {
        MediaView(
            url: channel.url,
            title: channel.name,
            subtitle: channel.tagline,
            video: channel.kind == .tv,
            live: true)
        .navigationTitle(channel.name)
    }
}

struct WatchView: View {
    let show: Show
    let episode: Episode

    var body: some View {
        MediaView(
            url: episode.mediaURL,
            title: episode.title,
            subtitle: show.title,
            video: episode.kind == .tv,
            live: false)
        .navigationTitle(episode.title)
    }
}

struct MediaView: View {
    let url: URL
    let title: String
    let subtitle: String
    let video: Bool
    let live: Bool

    @State private var playback = Playback.shared

    var body: some View {
        // Exactly one PlayerHost, always the second child of this ZStack, so its
        // identity is stable across channel changes and TV <-> radio: SwiftUI reuses
        // the one AVPlayerView instead of standing up a second one on the same player.
        ZStack(alignment: .bottom) {
            if video {
                Color.black
            } else {
                audioBackdrop
            }

            PlayerHost(controlsStyle: video ? .floating : .inline)
                .frame(maxWidth: video ? .infinity : 460)
                .frame(maxHeight: video ? .infinity : 48)
                .padding(.bottom, video ? 0 : 40)
        }
        .overlay(alignment: .topLeading) {
            if live && video { LiveBadge().padding(16) }
        }
        .overlay { overlay }
        .onAppear { playback.retain() }
        .onDisappear { playback.release() }
        .onChange(of: url, initial: true) {
            playback.play(url, title: title, subtitle: subtitle, live: live)
        }
    }

    private var audioBackdrop: some View {
        VStack(spacing: 24) {
            Spacer()
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.accentColor.gradient)
                .frame(width: 220, height: 220)
                .overlay {
                    Image(systemName: live ? "dot.radiowaves.left.and.right" : "waveform")
                        .font(.system(size: 76, weight: .light))
                        .foregroundStyle(.white)
                }
                .shadow(radius: 16, y: 8)
            VStack(spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            if live { LiveBadge() }

            // Explicit volume, rather than trusting the inline control bar to offer
            // one: for an audio-only item AVPlayerView leaves it out.
            HStack(spacing: 10) {
                Button {
                    playback.isMuted.toggle()
                } label: {
                    Image(systemName: playback.isMuted || playback.volume == 0
                        ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.borderless)
                .help(playback.isMuted ? "Sláa ljóð á" : "Sláa ljóð av")

                Slider(
                    value: Binding(
                        get: { playback.isMuted ? 0 : playback.volume },
                        set: { newValue in
                            playback.volume = newValue
                            if newValue > 0 { playback.isMuted = false }
                        }),
                    in: 0...1)
            }
            .frame(maxWidth: 260)
            .foregroundStyle(.secondary)

            Spacer()
            Spacer().frame(height: 48)  // room for the control bar pinned below
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var overlay: some View {
        if let failure = playback.failure {
            ContentUnavailableView {
                Label("Kundi ikki spæla", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Royn aftur") { playback.retry() }
                    .buttonStyle(.borderedProminent)
            }
            .background(.background)
        } else if playback.loading {
            ProgressView().controlSize(.large)
        }
    }
}

private struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor, in: Capsule())
    }
}
