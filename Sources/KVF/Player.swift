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

    @ObservationIgnored private var currentURL: URL?
    @ObservationIgnored private var nowPlaying = (title: "", subtitle: "", live: false)
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var settingObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        player.volume = defaults.object(forKey: "kvf.volume") as? Float ?? 1
        player.isMuted = defaults.bool(forKey: "kvf.muted")
        settingObservations = [
            player.observe(\.volume) { player, _ in
                UserDefaults.standard.set(player.volume, forKey: "kvf.volume")
            },
            player.observe(\.isMuted) { player, _ in
                UserDefaults.standard.set(player.isMuted, forKey: "kvf.muted")
            },
            // Keeps Now Playing in sync when the user pauses from AVPlayerView's
            // own controls rather than a media key.
            player.observe(\.timeControlStatus) { _, _ in
                Task { @MainActor in Playback.shared.publishNowPlaying() }
            },
        ]
        configureRemoteCommands()
    }

    /// Called from a player view's `onAppear`. SwiftUI builds the detail view twice
    /// at launch and then tears the first copy down, so appearances are refcounted —
    /// stopping on that stray `onDisappear` used to kill playback before it started.
    func attach(_ url: URL, title: String, subtitle: String, live: Bool) {
        viewers += 1
        play(url, title: title, subtitle: subtitle, live: live)
    }

    func detach() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { stop() }
    }

    private func play(_ url: URL, title: String, subtitle: String, live: Bool) {
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
struct PlayerHost: NSViewRepresentable {
    let player: AVPlayer
    var controlsStyle: AVPlayerViewControlsStyle = .floating

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = controlsStyle == .floating
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
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

private struct MediaView: View {
    let url: URL
    let title: String
    let subtitle: String
    let video: Bool
    let live: Bool

    @State private var playback = Playback.shared

    var body: some View {
        Group {
            if video {
                PlayerHost(player: playback.player)
                    .background(.black)
                    .overlay(alignment: .topLeading) {
                        if live { LiveBadge().padding(16) }
                    }
            } else {
                audioLayout
            }
        }
        .overlay { overlay }
        .onAppear { playback.attach(url, title: title, subtitle: subtitle, live: live) }
        .onDisappear { playback.detach() }
    }

    private var audioLayout: some View {
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
            PlayerHost(player: playback.player, controlsStyle: .inline)
                .frame(height: 40)
                .frame(maxWidth: 460)
            Spacer()
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
