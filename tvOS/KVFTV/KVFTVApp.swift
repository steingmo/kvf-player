import AVKit
import SwiftUI

@main
struct KVFTVApp: App {
    init() {
        // The default shared cache is far too small to hold a gridful of artwork.
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            VitBrowseView()
                .tabItem { Text("VIT") }
            BrowseView()
                .tabItem { Text("Sendingar") }
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
