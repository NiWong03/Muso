import Foundation
import Combine

struct QueueEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let video: MusicVideo
    let localURL: URL?
    init(video: MusicVideo, localURL: URL? = nil) { id = UUID(); self.video = video; self.localURL = localURL }
}

@MainActor
final class PlaybackQueueStore: ObservableObject {
    @Published private(set) var entries: [QueueEntry] = []
    @Published private(set) var index = 0
    @Published var autoplay: Bool = true { didSet { save() } }
    private var preservesCollectionOrder = false
    private var radioHistory: [MusicVideo] = []
    var radioExclusions: [MusicVideo] { radioHistory + entries.map(\.video) }
    private let defaults: UserDefaults
    private var key = "muso.queue.guest"
    var current: QueueEntry? { entries.indices.contains(index) ? entries[index] : nil }
    var hasNext: Bool { index + 1 < entries.count }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults; restore() }
    func switchAccount(_ userID: String?) { key = "muso.queue." + (userID ?? "guest"); restore() }
    func replace(_ entries: [QueueEntry], startAt: Int, preserveOrder: Bool = false) {
        preservesCollectionOrder = preserveOrder
        radioHistory = []
        let selected = entries.indices.contains(startAt) ? entries[startAt] : entries.first
        self.entries = preserveOrder ? entries : deduplicated(entries, preserving: selected)
        index = selected.flatMap { selected in self.entries.firstIndex(where: { $0.id == selected.id }) } ?? 0
        save()
    }
    func replaceCollection(_ videos: [MusicVideo], startingAt index: Int) {
        guard videos.indices.contains(index) else { return }
        replace(videos[index...].map { QueueEntry(video: $0) }, startAt: 0, preserveOrder: true)
    }

    func append(_ videos: [MusicVideo]) {
        entries += QueueDeduplicator.filter(videos, excluding: radioExclusions).map { QueueEntry(video: $0) }
        // Trim old played entries, never upcoming tracks, as autoplay grows the queue.
        if entries.count > 200 && index > 0 {
            let count = min(index, entries.count - 200)
            radioHistory = Array((radioHistory + entries.prefix(count).map(\.video)).suffix(1000))
            entries.removeFirst(count); index -= count
        }
        save()
    }
    /// An explicitly queued playlist retains its order and repeated tracks, including after restore.
    func enqueueCollection(_ videos: [MusicVideo], next: Bool = false) {
        guard !videos.isEmpty else { return }
        preservesCollectionOrder = true
        let destination = next && current != nil ? index + 1 : entries.count
        entries.insert(contentsOf: videos.map { QueueEntry(video: $0) }, at: destination)
        save()
    }

    /// Explicit enqueue relocates an existing posting instead of adding a duplicate.
    @discardableResult func enqueue(_ video: MusicVideo, next: Bool = false) -> Bool {
        if let current, matches(current.video, video) { return false }
        let entry: QueueEntry
        if let position = entries.firstIndex(where: { matches($0.video, video) }) {
            entry = entries.remove(at: position)
            if position < index { index -= 1 }
        } else { entry = QueueEntry(video: video) }
        let destination = next && !entries.isEmpty ? min(index + 1, entries.count) : entries.count
        entries.insert(entry, at: destination)
        save()
        return true
    }

    /// SwiftUI List offsets are relative to the upcoming section, never the playing track.
    func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        let start = min(index + 1, entries.count)
        var upcoming = Array(entries.dropFirst(start))
        guard !offsets.isEmpty, offsets.allSatisfy({ upcoming.indices.contains($0) }),
              (0...upcoming.count).contains(destination) else { return }
        let moving = offsets.sorted().map { upcoming[$0] }
        let insertion = destination - offsets.filter { $0 < destination }.count
        for offset in offsets.sorted(by: >) { upcoming.remove(at: offset) }
        upcoming.insert(contentsOf: moving, at: insertion)
        entries = Array(entries.prefix(start)) + upcoming
        save()
    }

    func move(_ id: UUID, to targetID: UUID) {
        guard let source = entries.firstIndex(where: { $0.id == id }), source > index,
              let target = entries.firstIndex(where: { $0.id == targetID }), target > index,
              source != target else { return }
        let entry = entries.remove(at: source)
        entries.insert(entry, at: target)
        save()
    }

    func moveToEnd(_ id: UUID) {
        guard let last = entries.last else { return }
        move(id, to: last.id)
    }

    private func matches(_ lhs: MusicVideo, _ rhs: MusicVideo) -> Bool {
        QueueDeduplicator.isDuplicate(lhs, rhs)
    }

    private func deduplicated(_ values: [QueueEntry], preserving selected: QueueEntry?) -> [QueueEntry] {
        var ids = Set<String>()
        var songs = Set<String>()
        return values.filter { entry in
            if let selected, entry.id != selected.id, matches(entry.video, selected.video) { return false }
            guard !ids.contains(entry.video.id), !songs.contains(entry.video.songIdentity) else { return false }
            ids.insert(entry.video.id); songs.insert(entry.video.songIdentity)
            return true
        }
    }

    func select(_ id: UUID) { if let next = entries.firstIndex(where: { $0.id == id }) { index = next; save() } }
    @discardableResult func advance() -> Bool {
        guard hasNext else { return false }; index += 1; save(); return true
    }
    @discardableResult func previous() -> Bool {
        guard index > 0 else { return false }; index -= 1; save(); return true
    }
    func remove(_ id: UUID) {
        guard let position = entries.firstIndex(where: { $0.id == id }), position != index else { return }
        entries.remove(at: position)
        if position < index { index -= 1 }
        save()
    }
    func moveUp(_ id: UUID) {
        guard let position = entries.firstIndex(where: { $0.id == id }), position > index + 1 else { return }
        entries.swapAt(position, position - 1); save()
    }
    func clear() { entries = []; radioHistory = []; index = 0; save() }
    private struct State: Codable { let entries: [QueueEntry]; let index: Int; let autoplay: Bool; let radioHistory: [MusicVideo]?; let preservesCollectionOrder: Bool? }
    private func save() {
        if let data = try? JSONEncoder().encode(State(entries: entries, index: index, autoplay: autoplay, radioHistory: radioHistory, preservesCollectionOrder: preservesCollectionOrder)) { defaults.set(data, forKey: key) }
    }
    private func restore() {
        let state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        radioHistory = state?.radioHistory ?? []
        preservesCollectionOrder = state?.preservesCollectionOrder ?? false
        let saved = state?.entries ?? []
        let savedIndex = min(max(0, state?.index ?? 0), max(0, saved.count - 1))
        let selected = saved.indices.contains(savedIndex) ? saved[savedIndex] : nil
        entries = preservesCollectionOrder ? saved : deduplicated(saved, preserving: selected)
        index = selected.flatMap { current in entries.firstIndex(where: { $0.id == current.id }) } ?? 0
        autoplay = state?.autoplay ?? true
    }
}
