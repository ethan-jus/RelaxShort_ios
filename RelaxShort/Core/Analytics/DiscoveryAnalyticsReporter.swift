import Foundation

// MARK: - Transport + QueueStore + Reporter (Task30 R4B-1)

protocol DiscoveryEventTransport: Sendable {
    func send(events: [DiscoveryEvent]) async throws -> DiscoveryEventBatchResponseDTO
}

struct APIClientDiscoveryEventTransport: DiscoveryEventTransport {
    func send(events: [DiscoveryEvent]) async throws -> DiscoveryEventBatchResponseDTO {
        try await APIClient.shared.requestData(.discoveryEvents(.init(events: events)))
    }
}

struct DiscoveryEventQueueStore: Sendable {
    let fileURL: URL
    func load() -> [DiscoveryEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do { return try JSONDecoder.discoveryDecoder().decode([DiscoveryEvent].self, from: data) }
        catch {
            let ts = Int(Date().timeIntervalSince1970)
            let corruptURL = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(ts).json")
            try? FileManager.default.moveItem(at: fileURL, to: corruptURL)
            Logger.analytics.debug("队列文件损坏，已隔离: \(corruptURL.lastPathComponent)")
            return []
        }
    }
    func save(_ events: [DiscoveryEvent]) throws {
        try JSONEncoder.discoveryEncoder().encode(events).write(to: fileURL, options: .atomic)
    }
    static func `default`() -> DiscoveryEventQueueStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DiscoveryEventQueueStore(fileURL: dir.appendingPathComponent("discovery_event_queue.json"))
    }
}

actor DiscoveryAnalyticsReporter {
    private var queue: [DiscoveryEvent]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private let transport: any DiscoveryEventTransport
    private let store: DiscoveryEventQueueStore
    private let maxQueue: Int; private let batch: Int; private let delayNS: UInt64

    init(transport: any DiscoveryEventTransport = APIClientDiscoveryEventTransport(),
         store: DiscoveryEventQueueStore = .default(), maxQueue: Int = 500, batch: Int = 20, delayNS: UInt64 = 15_000_000_000) {
        self.transport = transport; self.store = store; self.maxQueue = maxQueue; self.batch = batch; self.delayNS = delayNS
        self.queue = store.load()
    }

    func track(_ event: DiscoveryEvent) async {
        guard !queue.contains(where: { $0.eventID == event.eventID }) else { return }
        queue.append(event)
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        try? store.save(queue)
        if queue.count >= batch { await flush() } else { scheduleFlushIfNeeded() }
    }

    func flush() async {
        guard !isFlushing, !queue.isEmpty else { return }
        flushTask?.cancel(); flushTask = nil; isFlushing = true; defer { isFlushing = false }
        let batchEvents = Array(queue.prefix(batch))
        do {
            let r = try await sendWithRetry(batchEvents)
            guard r.acceptedCount + r.duplicateCount == batchEvents.count else { return }
            remove(batchEvents)
        } catch let e as NetworkError {
            switch e {
            case .unauthorized: remove(batchEvents)
            case .badStatus(let code) where (400..<500).contains(code):
                if code == 408 || code == 429 { break }
                remove(batchEvents)
            default: break }
        } catch let e as APIError {
            if let code = e.statusCode,
               (400..<500).contains(code),
               code != 408,
               code != 429 {
                remove(batchEvents)
            }
        } catch { }
    }

    func flushForBackground() async {
        guard !isFlushing, !queue.isEmpty else { return }
        isFlushing = true; defer { isFlushing = false }
        let batchEvents = Array(queue.prefix(batch))
        do {
            let r = try await transport.send(events: batchEvents)
            if r.acceptedCount + r.duplicateCount == batchEvents.count { remove(batchEvents) }
        } catch let e as NetworkError {
            switch e {
            case .unauthorized: remove(batchEvents)
            case .badStatus(let code) where (400..<500).contains(code):
                if code == 408 || code == 429 { break }
                remove(batchEvents)
            default: break }
        } catch let e as APIError {
            if let code = e.statusCode,
               (400..<500).contains(code),
               code != 408,
               code != 429 {
                remove(batchEvents)
            }
        } catch { }
    }

    private func sendWithRetry(_ b: [DiscoveryEvent]) async throws -> DiscoveryEventBatchResponseDTO {
        let delays: [UInt64] = [0, 2, 5, 15, 60]; var last: Error = NetworkError.invalidResponse
        for s in delays {
            if s > 0 { do { try await Task.sleep(nanoseconds: s * 1_000_000_000) } catch { throw error } }
            do { return try await transport.send(events: b) }
            catch let e as NetworkError {
                switch e {
                case .unauthorized: throw e
                case .badStatus(let code) where (400..<500).contains(code):
                    if code == 408 || code == 429 { break }
                    throw e
                default: break }
                last = e
            } catch let e as APIError {
                if let code = e.statusCode,
                   (400..<500).contains(code),
                   code != 408,
                   code != 429 {
                    throw e
                }
                last = e
            } catch { last = error }
        }
        throw last
    }

    private func remove(_ b: [DiscoveryEvent]) {
        let ids = Set(b.map(\.eventID)); queue.removeAll { ids.contains($0.eventID) }; try? store.save(queue)
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        let d = delayNS
        flushTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: d); await self?.runScheduled() }
            catch { }
        }
    }
    private func runScheduled() async { flushTask = nil; await flush() }
}
