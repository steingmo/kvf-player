import KVFKit
import SwiftUI

struct GuideView: View {
    let kind: Kind

    @State private var date = todayDateString()
    @State private var state: Loadable<GuideDay> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingState(message: nil) {}
            case .failed(let message):
                LoadingState(message: message) { await load() }
            case .loaded(let day):
                List {
                    ForEach(day.entries) { GuideRow(entry: $0) }
                }
            }
        }
        .navigationTitle(kind == .tv ? "Sjónvarpsskrá" : "Útvarpsskrá")
        .navigationSubtitle(formatGuideDate(date))
        .toolbar {
            ToolbarItemGroup {
                Button("Í dag") { date = todayDateString() }
                    .disabled(date == todayDateString())
                Button {
                    date = addDays(-1, to: date)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Fyrri dagur")
                Button {
                    date = addDays(1, to: date)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Næsti dagur")
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

private struct GuideRow: View {
    let entry: GuideEntry

    var body: some View {
        if entry.hasDetail {
            DisclosureGroup {
                detail
            } label: {
                header
            }
        } else {
            header
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.time)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title).fontWeight(entry.current ? .semibold : .regular)
                    if entry.current {
                        Text("Í GONGD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                    }
                    if entry.restricted {
                        Text("Bert í Føroyum")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = entry.image {
                // Fit, not fill: these thumbnails vary in aspect and fill cropped them.
                AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
                .frame(maxWidth: 320, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !entry.description.isEmpty {
                Text(entry.description).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
    }
}
