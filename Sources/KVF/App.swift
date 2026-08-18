import KVFKit
import SwiftUI

@main
struct KVFApp: App {
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 520, minHeight: 460)
                .tint(.kvf)
        }
        .defaultSize(width: 1080, height: 680)
        .commands { CheckForUpdatesCommand(updater: updater) }

        // VIT shows expose no podcast feed and no stream URL in their markup, so
        // they open on the real kvf.fo page and use KVF's own player.
        WindowGroup("VIT", id: "vit", for: String.self) { $path in
            if let path { VitWebView(path: path) }
        }
        .defaultSize(width: 980, height: 720)
    }
}

extension Color {
    /// Kringvarp Føroya broadcaster red, lifted for dark mode so it stays legible.
    static let kvf = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1.0, green: 0.231, blue: 0.306, alpha: 1)
                : NSColor(srgbRed: 0.784, green: 0.063, blue: 0.180, alpha: 1)
        })
}

enum Route: Hashable {
    case channel(String)
    case guide(Kind)
    case browse(Kind)
    case vit
    case show(Show)
}

/// Pushed onto the detail stack from a show's episode list.
struct EpisodeRef: Hashable {
    let show: Show
    let episode: Episode
}

struct RootView: View {
    @State private var route: Route? = .channel(defaultChannelID)
    @State private var path = NavigationPath()
    @State private var favorites = Favorites.shared

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: Show.self) { ShowView(show: $0) }
                    .navigationDestination(for: EpisodeRef.self) { WatchView(show: $0.show, episode: $0.episode) }
            }
        }
        .onChange(of: route) { path = NavigationPath() }
    }

    private var sidebar: some View {
        List(selection: $route) {
            Section("Sjónvarp") {
                ForEach(channels.filter { $0.kind == .tv }) { row($0) }
            }
            Section("Útvarp") {
                ForEach(channels.filter { $0.kind == .radio }) { row($0) }
            }
            if !favorites.shows.isEmpty {
                Section("Uppáhald") {
                    ForEach(favorites.shows) { show in
                        Label(show.title, systemImage: "star.fill")
                            .tag(Route.show(show))
                    }
                }
            }
            Section("Skrá") {
                item("KVF Sjónvarp", "Sjónvarpsskrá", "calendar", .guide(.tv))
                item("Útvarp Føroya", "Útvarpsskrá", "calendar", .guide(.radio))
            }
            Section("Sendingar") {
                item("Sjónvarp", "Sendingar á kravi", "tv", .browse(.tv))
                item("Útvarp", "Sendingar á kravi", "radio", .browse(.radio))
                item("VIT", "Sendingar fyri børn", "figure.and.child.holdinghands", .vit)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ channel: Channel) -> some View {
        item(channel.name, channel.tagline, channel.kind == .tv ? "tv" : "radio", .channel(channel.id))
    }

    private func item(_ title: String, _ subtitle: String, _ symbol: String, _ tag: Route) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tag(tag)
    }

    @ViewBuilder private var detail: some View {
        switch route {
        case .channel(let id):
            if let channel = channel(id) { LiveView(channel: channel) }
        case .guide(let kind):
            GuideView(kind: kind)
        case .browse(let kind):
            BrowseView(kind: kind)
        case .vit:
            VitBrowseView()
        case .show(let show):
            ShowView(show: show)
        case nil:
            ContentUnavailableView("Vel eina sending", systemImage: "tv")
        }
    }
}
