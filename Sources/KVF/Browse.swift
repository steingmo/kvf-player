import KVFKit
import SwiftUI
import WebKit

enum Loadable<Value> {
    case loading
    case failed(String)
    case loaded(Value)
}

/// Shared loading / error presentation for the three kvf.fo-backed lists.
struct LoadingState: View {
    let message: String?
    let retry: () async -> Void

    var body: some View {
        if let message {
            ContentUnavailableView {
                Label("Kundi ikki lesa frá kvf.fo", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Royn aftur") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView().controlSize(.large)
        }
    }
}

// MARK: - Sendingar (on demand)

struct BrowseView: View {
    let kind: Kind

    @State private var state: Loadable<[Show]> = .loading
    @State private var search = ""
    @State private var favorites = Favorites.shared

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let shows):
                let matches = shows.filter {
                    search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                }
                if matches.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List {
                        ForEach(matches) { show in
                            NavigationLink(value: show) {
                                HStack {
                                    Text(show.title)
                                    Spacer()
                                    StarButton(show: show)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.faroese)
        .navigationSubtitle("Sendingar á kravi")
        .searchable(text: $search, prompt: "Leita eftir sending")
        .task(id: kind) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let shows = try await KVFService.shared.catalogue()
            state = .loaded(shows.filter { $0.kind == kind })
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct StarButton: View {
    let show: Show
    @State private var favorites = Favorites.shared

    var body: some View {
        Button {
            favorites.toggle(show)
        } label: {
            Image(systemName: favorites.contains(show) ? "star.fill" : "star")
                .foregroundStyle(favorites.contains(show) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help(favorites.contains(show) ? "Tak úr uppáhaldi" : "Legg í uppáhald")
    }
}

struct ShowView: View {
    let show: Show

    @State private var state: Loadable<ShowEpisodes> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let detail):
                List {
                    if let image = detail.image {
                        Section {
                            // Show artwork is square (1440x1440) — scaledToFill blew it up
                            // to cover the row and showed a magnified middle slice.
                            AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: {
                                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                            }
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    Section("\(detail.episodes.count) sendingar") {
                        ForEach(detail.episodes) { episode in
                            NavigationLink(value: EpisodeRef(show: show, episode: episode)) {
                                EpisodeRow(episode: episode)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(show.title)
        .toolbar { StarButton(show: show) }
        .task(id: show.id) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await KVFService.shared.episodes(feedID: show.feedID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(episode.title)
            HStack(spacing: 8) {
                Image(systemName: episode.kind == .tv ? "tv" : "waveform")
                if let date = episode.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                }
                if !formatDuration(episode.durationSec).isEmpty {
                    Text(formatDuration(episode.durationSec))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !episode.description.isEmpty {
                Text(episode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - VIT

struct VitBrowseView: View {
    @State private var state: Loadable<[VitShow]> = .loading
    @State private var search = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let shows):
                let matches = shows.filter {
                    search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                }
                List(matches) { show in
                    Button {
                        openWindow(id: "vit", value: show.path)
                    } label: {
                        HStack {
                            Text(show.title)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("VIT")
        .navigationSubtitle("Sendingar fyri børn")
        .searchable(text: $search, prompt: "Leita eftir sending")
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await KVFService.shared.vitShows())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct VitWebView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        if let url = resolveKVFURL(path) {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
