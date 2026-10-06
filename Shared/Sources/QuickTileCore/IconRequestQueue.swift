import Foundation

/// Queues every requested asset while bounding concurrent work and retries.
public struct IconRequestQueue {
    public struct Request {
        public let id: UUID
        public let key: String
        public let started: Date
    }
    private var waiting: [String] = []
    private var known = Set<String>()
    private var attempts: [String: Int] = [:]
    private var active: [UUID: Request] = [:]
    public init() {}
    public var pendingCount: Int { known.count }
    public mutating func enqueue(_ key: String) {
        if known.insert(key).inserted { waiting.append(key) }
    }
    public mutating func next(now: Date = Date(), limit: Int = 6) -> Request? {
        guard active.count < limit, !waiting.isEmpty else { return nil }
        let key = waiting.removeFirst()
        attempts[key, default: 0] += 1
        let request = Request(id: UUID(), key: key, started: now)
        active[request.id] = request
        return request
    }
    public func key(for id: UUID) -> String? { active[id]?.key }
    public mutating func complete(_ id: UUID) -> String? {
        guard let request = active.removeValue(forKey: id) else { return nil }
        known.remove(request.key); attempts.removeValue(forKey: request.key)
        return request.key
    }
    /// Returns an exhausted key so its placeholder can stop loading.
    public mutating func fail(_ id: UUID) -> String? {
        guard let request = active.removeValue(forKey: id) else { return nil }
        if attempts[request.key, default: 0] < 3 { waiting.append(request.key); return nil }
        known.remove(request.key); attempts.removeValue(forKey: request.key)
        return request.key
    }
    public mutating func expire(now: Date = Date()) -> [String] {
        let expired = active.values.filter { now.timeIntervalSince($0.started) > 12 }.map(\.id)
        return expired.compactMap { fail($0) }
    }
    public mutating func reconnect() {
        waiting.insert(contentsOf: active.values.map(\.key), at: 0)
        active.removeAll(); attempts.removeAll()
    }
}
