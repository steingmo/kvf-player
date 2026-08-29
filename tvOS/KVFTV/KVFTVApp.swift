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
    var body: some View {
        NavigationStack {
            List {
                Section("Sjónvarp") {
                    ForEach(channels.filter { $0.kind == .tv }) { channel in
                        NavigationLink(value: channel) {
                            row(channel)
                        }
                    }
                }
                Section("Útvarp") {
                    ForEach(channels.filter { $0.kind == .radio }) { channel in
                        NavigationLink(value: channel) {
                            row(channel)
                        }
                    }
                }
            }
            .navigationTitle("Beinleiðis")
            .navigationDestination(for: Channel.self) { channel in
                PlayerScreen(url: channel.url, title: channel.name)
            }
        }
    }

    private func row(_ channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(channel.name)
            Text(channel.tagline).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Player

struct PlayerScreen: View {
    let url: URL
    let title: String

    @State private var player = AVPlayer()

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
    }
}
