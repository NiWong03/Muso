import Foundation

struct MusicCollection: Identifiable, Equatable, Hashable {
    enum Kind: String { case album = "Album", playlist = "Playlist" }
    let id: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let kind: Kind
}

/// Reads collection navigation and ordered track shelves from SDK transport responses.
enum MusicCollectionParser {
    private static func text(_ value: Any?) -> String {
        guard let object = value as? [String: Any] else { return "" }
        return (object["simpleText"] as? String ?? (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? "").decodingHTMLEntities
    }

    private static func find(_ key: String, in value: Any) -> Any? {
        if let object = value as? [String: Any] {
            if let match = object[key] { return match }
            for name in object.keys.sorted() { if let match = find(key, in: object[name]!) { return match } }
        } else if let array = value as? [Any] {
            for child in array { if let match = find(key, in: child) { return match } }
        }
        return nil
    }

    static func collections(from data: Data) throws -> [MusicCollection] {
        let json = try JSONSerialization.jsonObject(with: data)
        if (json as? [String: Any])?["error"] != nil { throw MusicDiscoveryError.invalidResponse }
        var results: [MusicCollection] = []
        var seen = Set<String>()
        func walk(_ value: Any) {
            if let array = value as? [Any] { array.forEach(walk); return }
            guard let object = value as? [String: Any] else { return }
            for name in ["musicResponsiveListItemRenderer", "musicTwoRowItemRenderer"] {
                if let row = object[name] as? [String: Any] {
                    let columns = (row["flexColumns"] as? [[String: Any]] ?? []).compactMap { $0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] }
                    let titleObject = row["title"] ?? columns.first?["text"]
                    // Only the row/title destination identifies a collection, not artist/album bylines on songs.
                    let endpoint = (row["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
                        ?? find("browseEndpoint", in: titleObject ?? [:]) as? [String: Any]
                    guard let endpoint, let id = endpoint["browseId"] as? String else { return }
                    let pageType = find("pageType", in: endpoint) as? String ?? ""
                    let kind: MusicCollection.Kind
                    if pageType == "MUSIC_PAGE_TYPE_ALBUM" || id.hasPrefix("MPRE") { kind = .album }
                    else if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" || id.hasPrefix("VL") { kind = .playlist }
                    else { return }
                    let title = text(titleObject)
                    guard !title.isEmpty, seen.insert(id).inserted else { return }
                    let thumbs = find("thumbnails", in: row["thumbnail"] ?? [:]) as? [[String: Any]] ?? []
                    results.append(MusicCollection(id: id, title: title,
                        subtitle: text(row["subtitle"] ?? (columns.count > 1 ? columns[1]["text"] : nil)),
                        thumbnailURL: (thumbs.last?["url"] as? String).flatMap(URL.init(string:)), kind: kind))
                    return
                }
            }
            for key in object.keys.sorted() { walk(object[key]!) }
        }
        walk(json)
        return results
    }

    static func tracks(from data: Data) throws -> (videos: [MusicVideo], continuation: String?) {
        let json = try JSONSerialization.jsonObject(with: data)
        if (json as? [String: Any])?["error"] != nil { throw MusicDiscoveryError.invalidResponse }
        // Scope to the track shelf so album suggestions never become album tracks.
        let shelf = find("musicPlaylistShelfRenderer", in: json)
            ?? find("musicPlaylistShelfContinuation", in: json)
            ?? find("musicShelfContinuation", in: json)
            ?? find("musicShelfRenderer", in: json)
            ?? find("appendContinuationItemsAction", in: json)
        guard let shelf else { return ([], nil) }
        let scoped = try JSONSerialization.data(withJSONObject: shelf)
        let token = find("continuation", in: shelf) as? String
            ?? (find("continuationCommand", in: shelf) as? [String: Any])?["token"] as? String
        return (try MusicResponseParser.videos(from: scoped, deduplicate: false), token)
    }
}
