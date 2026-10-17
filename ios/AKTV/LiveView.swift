import SwiftUI

@MainActor
final class ChannelStore: ObservableObject {
    @Published var channels: [Channel] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do {
            channels = try await ChannelAPI.fetchChannels()
        } catch {
            self.error = "Couldn't load channels. Pull down to retry."
        }
        loading = false
    }

    func grouped(_ query: String) -> [(category: String, channels: [Channel])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = channels.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        return Dictionary(grouping: list, by: { $0.category })
            .map { (category: $0.key, channels: $0.value) }
            .sorted { $0.category < $1.category }
    }
}

struct LiveView: View {
    @StateObject private var store = ChannelStore()
    @State private var query = ""
    @State private var playing: Channel?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.grouped(query), id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.channels) { ch in
                            Button { playing = ch } label: { ChannelRow(channel: ch) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search channels")
            .navigationTitle("Live TV")
            .overlay {
                if store.channels.isEmpty {
                    if store.loading { ProgressView() }
                    else if let e = store.error { ContentUnavailableView(e, systemImage: "wifi.exclamationmark") }
                }
            }
            .refreshable { await store.load() }
            .task { if store.channels.isEmpty { await store.load() } }
            .fullScreenCover(item: $playing) { ch in
                PlayerScreen(channel: ch)
            }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: channel.logo)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(String(channel.name.prefix(2)).uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 36)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Text(channel.name)
                .font(.body.weight(.medium))
            Spacer()
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
    }
}
