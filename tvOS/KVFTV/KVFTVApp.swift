import AVKit
import KVFKit
import SwiftUI

@main
struct KVFTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            LiveView()
                .tabItem { Text("Beinleiðis") }
            BrowseView(kind: .tv)
                .tabItem { Text("Sjónvarp") }
            BrowseView(kind: .radio)
                .tabItem { Text("Útvarp") }
            VitBrowseView()
                .tabItem { Text("VIT") }
            GuideView()
                .tabItem { Text("Skrá") }
        }
    }
}

/// Loading / error state for the kvf.fo-backed screens.
enum Loadable<Value> {
    case loading
    case failed(String)
    case loaded(Value)
}

struct LoadingState: View {
    let message: String?
    let retry: () async -> Void

    var body: some View {
        if let message {
            VStack(spacing: 24) {
                Text("Kundi ikki lesa frá kvf.fo").font(.title2)
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button("Royn aftur") { Task { await retry() } }
            }
        } else {
            ProgressView()
        }
    }
}

// MARK: - Beinleiðis

struct LiveView: View {
    @State private var playing: Channel?

    private let columns = [
        GridItem(.flexible(), spacing: 60),
        GridItem(.flexible(), spacing: 60),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 60) {
                ForEach(channels) { channel in
                    Button {
                        playing = channel
                    } label: {
                        ChannelCard(channel: channel)
                    }
                    // The tvOS home-screen tile treatment: lifts and parallaxes on focus.
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        // Full screen, not a push: a pushed player keeps the tab bar on top of the video.
        .fullScreenCover(item: $playing) { channel in
            PlayerScreen(url: channel.url, title: channel.name)
        }
    }
}

private struct ChannelCard: View {
    let channel: Channel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: channel.kind == .tv
                    ? [Color(red: 0.16, green: 0.31, blue: 0.42), Color(red: 0.09, green: 0.17, blue: 0.24)]
                    : [Color(red: 0.42, green: 0.16, blue: 0.20), Color(red: 0.24, green: 0.09, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            VStack(spacing: 16) {
                Image(systemName: channel.kind == .tv ? "tv" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .light))
                Text(channel.name).font(.title2.weight(.semibold))
                Text(channel.tagline).font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(height: 300)
    }
}

// MARK: - Player

struct PlayerScreen: View {
    let url: URL
    let title: String

    @State private var player = AVPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .navigationTitle(title)
            // Keyed to the URL, not to appearing: the same screen can be reused.
            .task(id: url) {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            .onExitCommand { dismiss() }
    }
}
