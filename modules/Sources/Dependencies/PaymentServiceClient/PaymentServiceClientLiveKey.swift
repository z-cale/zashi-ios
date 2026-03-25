import ComposableArchitecture
import Foundation
import os

private let logger = Logger(subsystem: "co.zodl.payment", category: "PaymentServiceClient")

// MARK: - Configuration

actor PaymentServiceConfigStore {
    static let shared = PaymentServiceConfigStore()
    var baseURL = "http://localhost:3100"
}

// MARK: - Errors

private enum PaymentServiceError: LocalizedError {
    case httpError(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .invalidResponse:
            return "Invalid response from payment service"
        }
    }
}

// MARK: - Live Implementation

extension PaymentServiceClient: DependencyKey {
    public static let liveValue: Self = {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        @Sendable
        func baseURL() async -> String {
            await PaymentServiceConfigStore.shared.baseURL
        }

        @Sendable
        func get<T: Decodable>(_ path: String) async throws -> T {
            let url = URL(string: "\(await baseURL())\(path)")!
            logger.debug("GET \(path)")
            let (data, response) = try await URLSession.shared.data(from: url)
            let httpResponse = response as! HTTPURLResponse
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                throw PaymentServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            return try decoder.decode(T.self, from: data)
        }

        @Sendable
        func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
            let url = URL(string: "\(await baseURL())\(path)")!
            logger.debug("POST \(path)")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                throw PaymentServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            return try decoder.decode(T.self, from: data)
        }

        @Sendable
        func postNoBody<T: Decodable>(_ path: String) async throws -> T {
            let url = URL(string: "\(await baseURL())\(path)")!
            logger.debug("POST \(path)")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                throw PaymentServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            return try decoder.decode(T.self, from: data)
        }

        return Self(
            resolvePIRTag: { tag in
                try await get("/pir/\(tag)")
            },
            createPaymentLink: { request in
                try await post("/payment-link", body: request)
            },
            getPaymentLink: { id in
                try await get("/payment-link/\(id)")
            },
            claimPaymentLink: { id, request in
                try await post("/payment-link/\(id)/claim", body: request)
            },
            revokePaymentLink: { id in
                try await postNoBody("/payment-link/\(id)/revoke")
            },
            registerRelay: { request in
                try await post("/relay/register", body: request)
            },
            resolveRelayByAddress: { address in
                try await get("/relay/resolve/\(address)")
            },
            getRelayPubkey: { relayId in
                try await get("/relay/\(relayId)/pubkey")
            },
            postRelayEncaps: { relayId, request in
                try await post("/relay/\(relayId)/encaps", body: request)
            },
            getRelayStatus: { relayId, encapsId in
                try await get("/relay/\(relayId)/status/\(encapsId)")
            },
            transfer: { request in
                try await post("/transfer", body: request)
            },
            registerAlias: { alias, owner in
                struct AliasResponse: Codable { let alias: String; let owner: String }
                let _: AliasResponse = try await post("/address/alias", body: RegisterAliasRequest(alias: alias, owner: owner))
            },
            getTransactions: { address in
                try await get("/transactions/\(address)")
            },
            subscribeToEvents: { address in
                AsyncStream { continuation in
                    let task = Task {
                        guard let url = URL(string: "\(await baseURL())/events/\(address)") else {
                            continuation.finish()
                            return
                        }
                        do {
                            let (bytes, _) = try await URLSession.shared.bytes(from: url)
                            for try await line in bytes.lines {
                                if line.hasPrefix("event: transaction") {
                                    continuation.yield(())
                                }
                            }
                        } catch {
                            logger.debug("SSE connection ended: \(error)")
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            getBalance: { address in
                try await get("/balance/\(address)")
            }
        )
    }()
}
