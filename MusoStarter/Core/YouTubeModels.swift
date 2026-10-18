import Foundation

struct MusicVideo: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?

    init(id: String, title: String, channelTitle: String, thumbnailURL: URL?) {
        self.id = id
        self.title = title.decodingHTMLEntities
        self.channelTitle = channelTitle.decodingHTMLEntities
        self.thumbnailURL = thumbnailURL
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id),
                  title: try values.decode(String.self, forKey: .title),
                  channelTitle: try values.decode(String.self, forKey: .channelTitle),
                  thumbnailURL: try values.decodeIfPresent(URL.self, forKey: .thumbnailURL))
    }
}

extension String {
    /// Decode text entities without interpreting titles as HTML markup.
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">",
                     "nbsp": "\u{00A0}", "ndash": "–", "mdash": "—", "hellip": "…",
                     "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
                     "copy": "©", "reg": "®", "trade": "™"]
        let pattern = #/&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);/#
        return replacing(pattern) { match in
            let entity = String(match.1)
            if let replacement = named[entity] { return replacement }
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x") || entity.hasPrefix("#X")
                let digits = entity.dropFirst(hex ? 2 : 1)
                if let value = UInt32(digits, radix: hex ? 16 : 10),
                   value != 0, let scalar = UnicodeScalar(value) {
                    return String(scalar)
                }
            }
            return String(match.0)
        }
    }
}

protocol YouTubeServing {
    func video(for input: String) async throws -> MusicVideo
    func playableTrack(for video: MusicVideo) async throws -> PlayableTrack
}

enum YouTubeServiceError: LocalizedError {
    case invalidVideoLink
    case metadataUnavailable
    case noPlayableAudio

    var errorDescription: String? {
        switch self {
        case .invalidVideoLink: return "Paste a YouTube video link or an 11-character video ID. Search terms and playlist-only links are not supported."
        case .metadataUnavailable: return "YouTube could not provide details for this video. Try another video link."
        case .noPlayableAudio: return "No audio stream compatible with this device is available for this video."
        }
    }
}

extension MusicVideo {
    /// Match alternate postings while retaining meaningful versions (live, remix, acoustic).
    var songIdentity: String {
        func normalized(_ value: String) -> String {
            value.decodingHTMLEntities.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "[^a-z0-9\\p{L}]+", with: " ", options: .regularExpression)
                .split(separator: " ").joined(separator: " ")
        }
        let decorations = #"(?i)[\(\[]\s*(?:(?:official\s+)?(?:music\s+)?(?:video|audio)|(?:official\s+)?lyric(?:s|\s+video)?|visuali[sz]er|hd|4k)\s*[\)\]]"#
        var song = title.replacingOccurrences(of: decorations, with: "", options: .regularExpression)
        song = song.replacingOccurrences(of: #"(?i)\s*[-–]\s*(?:official\s+)?(?:music\s+video|video|audio|lyrics?)$"#, with: "", options: .regularExpression)
        song = song.replacingOccurrences(of: #"(?i)[\(\[]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?\s*[\)\]]|\s*[-–]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?$"#, with: "", options: .regularExpression)
        var artist = channelTitle.replacingOccurrences(of: #"(?i)(\s*-\s*topic|vevo|\s+official)$"#, with: "", options: .regularExpression)
        // Uploaded videos commonly embed the credited artist before the song title.
        if let separator = song.range(of: " - ") ?? song.range(of: " – ") {
            artist = String(song[..<separator.lowerBound])
            song = String(song[separator.upperBound...])
        }
        song = song.replacingOccurrences(of: #"(?i)\s*[-–]\s*(?:official\s+)?(?:music\s+video|video|audio|lyrics?)$"#, with: "", options: .regularExpression)
        let name = normalized(song)
        let credit = normalized(artist)
        guard !name.isEmpty, !credit.isEmpty, !["youtube", "youtube music", "unknown"].contains(credit) else { return "id:" + id }
        return credit + "|" + name
    }
}

/// Conservative metadata heuristics for automatic radio additions; no official-upload gate.
enum QueueDeduplicator {
    private static func words(_ text: String) -> Set<String> {
        Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private static func identity(_ video: MusicVideo) -> (artist: String, title: Set<String>, versions: Set<String>) {
        let cleaned = video.title.replacingOccurrences(
            of: #"(?i)\b(?:\d+\s*(?:hours?|hrs?)|on repeat|loop(?:ed)?|audio track)\b"#,
            with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\(\[]\s*[\)\]]"#, with: "", options: .regularExpression)
        let key = MusicVideo(id: video.id, title: cleaned, channelTitle: video.channelTitle, thumbnailURL: nil).songIdentity
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        let versionWords: Set<String> = ["remix", "live", "acoustic", "cover", "instrumental", "karaoke", "slowed", "sped", "nightcore"]
        return (parts.count == 2 ? parts[0] : "", words(parts.last ?? cleaned), words(cleaned).intersection(versionWords))
    }

    static func isDuplicate(_ lhs: MusicVideo, _ rhs: MusicVideo) -> Bool {
        if lhs.id == rhs.id { return true }
        let a = identity(lhs), b = identity(rhs)
        guard a.versions == b.versions else { return false }
        if lhs.songIdentity == rhs.songIdentity { return true }
        guard !a.artist.isEmpty, a.artist == b.artist, !a.title.isEmpty, !b.title.isEmpty else { return false }
        if a.title == b.title { return true }
        let overlap = a.title.intersection(b.title).count
        // Short titles and one-sided subset matches otherwise erase unrelated songs.
        guard overlap >= 3 else { return false }
        return Double(overlap) / Double(a.title.count) >= 0.8 && Double(overlap) / Double(b.title.count) >= 0.8
    }

    static func isLikelyMusic(_ video: MusicVideo) -> Bool {
        // Reject explicit non-music formats, while allowing uploads, remixes and performances.
        let nonMusic = #"(?i)\b(?:podcast|interview|reaction|reacts? to|tutorial|how to|walkthrough|gameplay|vlog|unboxing|press conference|news report|album review|song review|music review|behind the scenes|making of|explained)\b"#
        return video.title.range(of: nonMusic, options: .regularExpression) == nil
    }

    static func filter(_ candidates: [MusicVideo], excluding prior: [MusicVideo], ids: Set<String> = []) -> [MusicVideo] {
        var seen = prior
        return candidates.filter { candidate in
            guard !ids.contains(candidate.id), isLikelyMusic(candidate),
                  !seen.contains(where: { isDuplicate($0, candidate) }) else { return false }
            seen.append(candidate)
            return true
        }
    }
}
