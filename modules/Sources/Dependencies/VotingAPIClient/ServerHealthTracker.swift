import Foundation
import os

private let logger = Logger(subsystem: "co.electriccoin.voting", category: "HealthTracker")

// MARK: - Server Health Tracker

/// Tracks per-server health using a circuit breaker pattern.
/// Servers that fail repeatedly are temporarily excluded from share distribution,
/// with periodic probes to detect recovery.
actor ServerHealthTracker {
    static let shared = ServerHealthTracker()

    // MARK: - Circuit Breaker

    enum Circuit: Equatable {
        case closed
        case open(since: Date)
        case halfOpen

        static func == (lhs: Circuit, rhs: Circuit) -> Bool {
            switch (lhs, rhs) {
            case (.closed, .closed), (.halfOpen, .halfOpen):
                return true
            case let (.open(since: lhsSince), .open(since: rhsSince)):
                return lhsSince == rhsSince
            default:
                return false
            }
        }
    }

    struct ServerState {
        var circuit: Circuit = .closed
        var consecutiveFailures = 0
    }

    // MARK: - Constants

    private let failureThreshold = 3
    private let cooldownInterval: TimeInterval = 30

    // MARK: - State

    private var servers: [String: ServerState] = [:]
    private var probeTask: Task<Void, Never>?

    /// URLSession with a short timeout for health probes and share POSTs.
    private let probeSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    // MARK: - Initialization

    /// Populate the server map and run an initial parallel probe of all servers.
    /// Called when the CDN service config is loaded.
    func initialize(serverURLs: [String]) async {
        // Replace server map (preserving nothing from prior config)
        servers = Dictionary(uniqueKeysWithValues: serverURLs.map { ($0, ServerState()) })

        // Fire parallel probes so we know who's healthy before the first vote
        await probeAll()

        // Start background probing (replaces any existing loop)
        startBackgroundProbing()
    }

    // MARK: - Server Selection

    /// Returns servers whose circuit is closed or halfOpen.
    /// If all servers are open (or map is empty), returns ALL servers as a fallback
    /// so that voting is never blocked by the health tracker.
    func healthyServers() -> [String] {
        let now = Date()
        var healthy: [String] = []

        for (url, state) in servers {
            switch state.circuit {
            case .closed:
                healthy.append(url)
            case .open(let since) where now.timeIntervalSince(since) >= cooldownInterval:
                // Cooldown expired — transition to halfOpen and allow traffic
                servers[url]?.circuit = .halfOpen
                healthy.append(url)
            case .halfOpen:
                healthy.append(url)
            default:
                break
            }
        }

        // Graceful degradation: never return empty
        if healthy.isEmpty {
            logger.warning("All servers unhealthy — falling back to full list")
            return Array(servers.keys)
        }
        return healthy
    }

    // MARK: - State Updates

    func recordSuccess(for url: String) {
        guard var state = servers[url] else { return }
        let previous = state.circuit
        state.circuit = .closed
        state.consecutiveFailures = 0
        servers[url] = state
        if previous != .closed {
            logger.info("\(url, privacy: .public) recovered → closed")
        }
    }

    func recordFailure(for url: String) {
        guard var state = servers[url] else { return }
        state.consecutiveFailures += 1
        let failures = state.consecutiveFailures

        if failures >= failureThreshold && state.circuit == .closed {
            state.circuit = .open(since: Date())
            logger.warning("\(url, privacy: .public) tripped → open (after \(failures) failures)")
        } else if state.circuit == .halfOpen {
            // halfOpen probe failed — re-open
            state.circuit = .open(since: Date())
            logger.warning("\(url, privacy: .public) halfOpen probe failed → open")
        }
        servers[url] = state
    }

    // MARK: - Health Probing

    /// Probe all servers in parallel with GET /api/v1/status.
    func probeAll() async {
        let urls = Array(servers.keys)
        guard !urls.isEmpty else { return }

        await withTaskGroup(of: (String, Bool).self) { group in
            for url in urls {
                group.addTask { [probeSession] in
                    let healthy = await Self.probe(url: url, session: probeSession)
                    return (url, healthy)
                }
            }
            for await (url, healthy) in group {
                if healthy {
                    recordSuccess(for: url)
                } else {
                    recordFailure(for: url)
                }
            }
        }
    }

    /// Single server probe. Returns true if the server responds 200 within the timeout.
    private static func probe(url: String, session: URLSession) async -> Bool {
        guard let endpoint = URL(string: "\(url)/api/v1/status") else { return false }
        do {
            let (_, response) = try await session.data(from: endpoint)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Background Probing

    private func startBackgroundProbing() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await self?.probeAll()
            }
        }
    }

    func stopBackgroundProbing() {
        probeTask?.cancel()
        probeTask = nil
    }
}
