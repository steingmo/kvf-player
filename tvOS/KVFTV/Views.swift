import KVFKit
import SwiftUI

// MARK: - Sendingar

struct BrowseView: View {
    let kind: Kind

    @State private var state: Loadable<[Show]> = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    LoadingState(message: nil) {}
                case .failed(let message):
                    LoadingState(message: message) { await load() }
                case .loaded(let shows):
                    List(shows) { show in
                        NavigationLink(value: show) { Text(show.title) }
                    }
                }
            }
            .navigationTitle(kind.faroese)
            .navigationDestination(for: Show.self) { ShowView(show: $0) }
        }
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

struct ShowView: View {
    let show: Show

    @State private var state: Loadable<ShowEpisodes> = .loading
    @State private var playing: Episode?

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let detail):
                List(detail.episodes) { episode in
                    Button {
                        playing = episode
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                            HStack(spacing: 12) {
                                if let date = episode.date {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                }
                                if !formatDuration(episode.durationSec).isEmpty {
                                    Text(formatDuration(episode.durationSec))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(show.title)
        .fullScreenCover(item: $playing) { episode in
            PlayerScreen(url: episode.mediaURL, title: episode.title)
        }
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

// MARK: - VIT

struct VitBrowseView: View {
    @State private var state: Loadable<[VitShow]> = .loading

    private let vitColumns = Array(repeating: GridItem(.flexible(), spacing: 50), count: 4)

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    LoadingState(message: nil) {}
                case .failed(let message):
                    LoadingState(message: message) { await load() }
                case .loaded(let shows):
                    ScrollView {
                        LazyVGrid(columns: vitColumns, spacing: 50) {
                            ForEach(shows) { show in
                                NavigationLink(value: show) {
                                    VitCard(show: show)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.vertical, 40)
                    }
                }
            }
            .navigationTitle("VIT")
            .navigationDestination(for: VitShow.self) { VitShowView(show: $0) }
        }
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

private struct VitCard: View {
    let show: VitShow

    var body: some View {
        VStack(spacing: 0) {
            // kvf.fo's own thumbnails are 16:9.
            AsyncImage(url: show.image) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color(white: 0.16)
                    Image(systemName: "figure.and.child.holdinghands")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 190)
            .clipped()

            Text(show.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .background(Color(white: 0.12))
        }
    }
}

struct VitShowView: View {
    let show: VitShow

    @State private var state: Loadable<VitShowDetail> = .loading
    @State private var playing: VitEpisode?

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let detail):
                List(detail.episodes) { episode in
                    Button {
                        playing = episode
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                            if let date = episode.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(show.title)
        .fullScreenCover(item: $playing) { episode in
            VitPlayerScreen(show: show, episode: episode)
        }
        .task(id: show.path) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await KVFService.shared.vitShow(show))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// VIT stream URLs only exist on the episode's own page, so resolve then play.
struct VitPlayerScreen: View {
    let show: VitShow
    let episode: VitEpisode

    @State private var state: Loadable<VitStream> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let stream):
                PlayerScreen(url: stream.url, title: episode.title)
            }
        }
        .task(id: episode.id) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await KVFService.shared.vitStream(path: show.path, sid: episode.sid))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Skrá

struct GuideView: View {
    @State private var kind: Kind = .tv
    @State private var date = todayDateString()
    @State private var state: Loadable<GuideDay> = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    LoadingState(message: nil) {}
                case .failed(let message):
                    LoadingState(message: message) { await load() }
                case .loaded(let day):
                    List(day.entries) { entry in
                        HStack(alignment: .top, spacing: 20) {
                            Text(entry.time).monospaced().foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).fontWeight(entry.current ? .semibold : .regular)
                                if !entry.subtitle.isEmpty {
                                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                if !entry.description.isEmpty {
                                    Text(entry.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind == .tv ? "Sjónvarpsskrá" : "Útvarpsskrá")
            .safeAreaInset(edge: .top) {
                HStack(spacing: 20) {
                    Picker("", selection: $kind) {
                        Text("Sjónvarp").tag(Kind.tv)
                        Text("Útvarp").tag(Kind.radio)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)

                    Spacer()
                    Button("Fyrri") { date = addDays(-1, to: date) }
                    Text(formatGuideDate(date)).foregroundStyle(.secondary)
                    Button("Næsti") { date = addDays(1, to: date) }
                }
                .padding(.horizontal, 48)
            }
        }
        .task(id: "\(kind.rawValue):\(date)") { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await KVFService.shared.guideDay(kind: kind, date: date))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
