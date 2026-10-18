import Foundation

/// Accepts only a single YouTube video, never arbitrary hosts or playlist IDs.
enum YouTubeVideoInput {
    static func videoID(from input: String) -> String? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if validID(input) { return input }
        let candidate = input.contains("://") ? input : "https://" + input
        guard let url = URLComponents(string: candidate),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        switch host {
        case "youtu.be", "www.youtu.be":
            id = parts.count == 1 ? parts.first : nil
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com":
            if url.path == "/watch" {
                id = url.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) {
                id = parts[1]
            } else { id = nil }
        default: return nil
        }
        guard let id, validID(id) else { return nil }
        return id
    }

    private static func validID(_ value: String) -> Bool {
        value.utf8.count == 11 && value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
}
