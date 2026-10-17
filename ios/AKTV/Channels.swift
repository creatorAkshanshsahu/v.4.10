import Foundation

/// A live channel from the TG TV public API (same feed as the Android app).
struct Channel: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let logo: String
}

/// One stream link. iPhone (AVPlayer) plays HLS without DRM; MPD / ClearKey streams are skipped.
struct StreamSource {
    let url: URL
    let isDash: Bool
    let hasDRM: Bool
    var playable: Bool { !isDash && !hasDRM }
}

enum ChannelAPI {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let site = "https://livetgtv.lovable.app/api/public/channels"

    static func fetchChannels() async throws -> [Channel] {
        var req = URLRequest(url: URL(string: site)!, timeoutInterval: 15)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["channels"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        return arr.compactMap { o in
            let id = (o["id"] as? String) ?? ""
            let name = ((o["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !name.isEmpty else { return nil }
            let cat = ((o["category"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            return Channel(id: id, name: name, category: cat.isEmpty ? "Other" : cat, logo: (o["logo"] as? String) ?? "")
        }
    }

    /// Stream links for one channel, in the order the site gives them (playable ones only).
    static func streams(for channel: Channel) async throws -> [StreamSource] {
        var req = URLRequest(url: URL(string: "\(site)/\(channel.id)")!, timeoutInterval: 12)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let hasDRM = (o["drm"] as? [String: Any]) != nil
        var list: [StreamSource] = []

        func add(_ text: String, hint: String, drm: Bool) {
            guard text.hasPrefix("http"), let u = URL(string: text) else { return }
            if list.contains(where: { $0.url == u }) { return }
            let path = u.path.lowercased()
            let dash = path.hasSuffix(".mpd") || (!path.hasSuffix(".m3u8") && hint.lowercased() == "dash")
            list.append(StreamSource(url: u, isDash: dash, hasDRM: drm))
        }
        for s in (o["sources"] as? [String]) ?? [] { add(s, hint: "", drm: hasDRM) }
        for sv in (o["servers"] as? [[String: Any]]) ?? [] {
            add((sv["playable"] as? String) ?? "", hint: (sv["type"] as? String) ?? "", drm: false)
        }
        return list.filter { $0.playable }
    }
}
