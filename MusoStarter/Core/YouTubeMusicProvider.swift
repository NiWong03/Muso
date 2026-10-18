import Foundation

protocol YouTubeMusicProviding {
    func searchCatalog(_ query: String) async throws -> YouTubeSearchPage
    func tracks(in collection: MusicCollection) async throws -> [MusicVideo]
    func search(_ query: String) async throws -> [MusicVideo]
    func suggestions(_ query: String) async throws -> [String]
    func trending() async throws -> [MusicVideo]
    func likedMusic() async throws -> [MusicVideo]
    func home() async throws -> [MusicVideo]
    func radio(videoID: String) async throws -> [MusicVideo]
}

extension YouTubeMusicProviding {
    func searchCatalog(_ query: String) async throws -> YouTubeSearchPage {
        YouTubeSearchPage(videos: try await search(query), nextPageToken: nil)
    }
    func tracks(in collection: MusicCollection) async throws -> [MusicVideo] { throw MusicDiscoveryError.invalidResponse }
}

enum MusicDiscoveryError: LocalizedError {
    case signInRequired
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in with Google again to reconnect your music."
        case .invalidResponse: return "YouTube Music could not provide music right now. Please try again."
        }
    }
}

/// Adapts Music browse/next renderers not yet exposed by YouTubeSDK's typed API.
/// Transport and client identity are supplied by YouTubeSDK.
enum MusicResponseParser {
    static func videos(from data: Data, songsOnly: Bool = false, deduplicate: Bool = true) throws -> [MusicVideo] {
        let json = try JSONSerialization.jsonObject(with: data)
        if let object = json as? [String: Any], object["error"] != nil { throw MusicDiscoveryError.invalidResponse }
        var result: [MusicVideo] = []
        var ids = Set<String>()
        func text(_ value: Any?) -> String? {
            guard let object = value as? [String: Any] else { return value as? String }
            return object["simpleText"] as? String ?? (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        func musicType(_ value: Any?) -> String? {
            if let object = value as? [String: Any] {
                if let type = object["musicVideoType"] as? String { return type }
                for key in object.keys.sorted() { if let type = musicType(object[key]) { return type } }
            } else if let array = value as? [Any] {
                for item in array { if let type = musicType(item) { return type } }
            }
            return nil
        }
        func parse(_ row: [String: Any]) {
            if songsOnly {
                let type = musicType(row["navigationEndpoint"]) ?? musicType(row["overlay"])
                guard type == "MUSIC_VIDEO_TYPE_ATV" else { return }
            }
            guard row["musicItemRendererDisplayPolicy"] as? String != "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT" else { return }
            guard row["isPlayable"] as? Bool != false else { return }
            let endpoint = row["navigationEndpoint"] as? [String: Any]
            let watch = endpoint?["watchEndpoint"] as? [String: Any]
            let playlist = row["playlistItemData"] as? [String: Any]
            guard let id = row["videoId"] as? String ?? playlist?["videoId"] as? String ?? watch?["videoId"] as? String,
                  YouTubeVideoInput.videoID(from: id) == id else { return }
            let columns = (row["flexColumns"] as? [[String: Any]] ?? []).compactMap { $0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] }
            guard let title = text(row["title"]) ?? columns.first.flatMap({ text($0["text"]) }), !title.isEmpty else { return }
            guard !deduplicate || ids.insert(id).inserted else { return }
            let byline = row["longBylineText"] ?? row["shortBylineText"] ?? row["subtitle"] ?? (columns.count > 1 ? columns[1]["text"] : nil)
            let runs = (byline as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            let artists = runs.compactMap { run -> String? in
                let nav = run["navigationEndpoint"] as? [String: Any]
                let browse = nav?["browseEndpoint"] as? [String: Any]
                guard (browse?["browseId"] as? String)?.hasPrefix("UC") == true else { return nil }
                return run["text"] as? String
            }
            let artist = artists.isEmpty ? (text(byline)?.components(separatedBy: " • ").first ?? "YouTube Music") : artists.joined(separator: ", ")
            let thumbnail = row["thumbnail"] as? [String: Any]
            let musicThumbnail = thumbnail?["musicThumbnailRenderer"] as? [String: Any]
            let image = musicThumbnail?["thumbnail"] as? [String: Any] ?? thumbnail
            let thumbs = image?["thumbnails"] as? [[String: Any]] ?? []
            let url = (thumbs.last?["url"] as? String).flatMap(URL.init(string:))
            result.append(MusicVideo(id: id, title: title, channelTitle: artist, thumbnailURL: url))
        }
        func walk(_ value: Any) {
            if let array = value as? [Any] { array.forEach(walk) }
            else if let object = value as? [String: Any] {
                for key in ["playlistPanelVideoRenderer", "musicResponsiveListItemRenderer", "musicTwoRowItemRenderer"] {
                    if let row = object[key] as? [String: Any] { parse(row); return }
                }
                // Arrays retain the ordering of YouTube Music's queue.
                for key in object.keys.sorted() { if let child = object[key] { walk(child) } }
            }
        }
        walk(json)
        return result
    }
}

@MainActor
enum MusicRequestAuthorization {
    static func headers(requiresSignIn: Bool, accessToken: () async throws -> String?) async throws -> [String: String] {
        // Public InnerTube requests must not inherit a Data API OAuth grant.
        // Even refreshing that grant here can incorrectly block public search/radio.
        guard requiresSignIn else { return [:] }
        guard let token = try await accessToken(), !token.isEmpty else { throw MusicDiscoveryError.signInRequired }
        return ["Authorization": "Bearer " + token]
    }
}
