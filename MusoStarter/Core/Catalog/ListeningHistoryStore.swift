import Foundation
import Combine

@MainActor
final class ListeningHistoryStore: ObservableObject {
    @Published private(set) var recent: [MusicVideo] = []
    private let defaults: UserDefaults
    private var storageKey: String?
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func switchAccount(_ userID: String?) {
        storageKey = userID.map { "muso.history." + $0 }
        recent = storageKey.flatMap { defaults.data(forKey: $0) }.flatMap { try? JSONDecoder().decode([MusicVideo].self, from: $0) } ?? []
    }
    func record(_ video: MusicVideo) {
        guard let storageKey else { return }
        recent.removeAll { $0.id == video.id }
        recent.insert(video, at: 0)
        recent = Array(recent.prefix(50))
        if let data = try? JSONEncoder().encode(recent) { defaults.set(data, forKey: storageKey) }
    }
    func clear() {
        if let storageKey { defaults.removeObject(forKey: storageKey) }
        recent = []
    }
}
