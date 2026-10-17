import SwiftUI
import WebKit

/// Movies and series: TMDB catalogue (same key and shelves idea as the Android app).
/// Playback uses the TGVID player page inside WKWebView, which is the same provider the Android app uses.
enum TitleKind {
    case movie, series
    var tmdb: String { self == .movie ? "movie" : "tv" }
    var embed: String { self == .movie ? "movie" : "tv" }
    var title: String { self == .movie ? "Movies" : "Series" }
}

struct TMDBTitle: Identifiable, Decodable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let overview: String?
    var display: String { title ?? name ?? "" }
    var poster: URL? { poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") } }
}

private struct TMDBList: Decodable { let results: [TMDBTitle] }

struct Watch: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

@MainActor
final class CatalogueStore: ObservableObject {
    static let apiKey = "e86d249e1b4fc2dcd7d1f1cb09a004f8"
    @Published var items: [TMDBTitle] = []
    @Published var error: String?

    func load(_ kind: TitleKind) async {
        error = nil
        let url = "https://api.themoviedb.org/3/trending/\(kind.tmdb)/week?api_key=\(Self.apiKey)&language=en-US"
        do {
            let (data, resp) = try await URLSession.shared.data(from: URL(string: url)!)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            items = try JSONDecoder().decode(TMDBList.self, from: data).results
                .filter { $0.poster_path != nil }
        } catch {
            self.error = "Couldn't load \(kind.title.lowercased()). Pull down to retry."
        }
    }
}

struct MoviesView: View {
    let kind: TitleKind
    @StateObject private var store = CatalogueStore()
    @State private var watching: Watch?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.items) { t in
                        Button {
                            watching = Watch(title: t.display, url: embedURL(t.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: t.poster) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.white.opacity(0.08)
                                }
                                .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(t.display)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay {
                if store.items.isEmpty, let e = store.error {
                    ContentUnavailableView(e, systemImage: "wifi.exclamationmark")
                }
            }
            .navigationTitle("Trending " + kind.title)
            .refreshable { await store.load(kind) }
            .task { if store.items.isEmpty { await store.load(kind) } }
            .fullScreenCover(item: $watching) { w in
                NavigationStack {
                    WebPlayer(url: w.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(w.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { watching = nil }
                            }
                        }
                }
            }
        }
    }

    private func embedURL(_ id: Int) -> URL {
        let base = "https://tgvid.lovable.app/embed/\(kind.embed)/\(id)"
        let q = kind == .movie ? "?color=e50914&back=false" : "?color=e50914&back=false&autoplayNextEp=true&episodeSelector=true"
        return URL(string: base + (kind == .series ? "/1/1" : "") + q)!
    }
}

struct WebPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.allowsPictureInPictureMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.backgroundColor = .black
        v.isOpaque = false
        v.load(URLRequest(url: url))
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
