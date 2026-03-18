import Foundation

// MARK: - Mock Payment Key

public struct MockPaymentKey: Equatable {
    public let label: String
    public let hex: String

    public var truncated: String {
        let prefix = String(hex.prefix(8))
        let suffix = String(hex.suffix(8))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Mock Payment

public struct MockPayment: Equatable, Identifiable {
    public let id: UUID
    public let amount: String
    public let timestamp: Date
    public let senderLabel: String
    public let viaRelay: Bool
}

// MARK: - Tachyon URI Helpers

public enum TachyonURI {
    public static func paymentRequest(pk: String, amount: String) -> String {
        "tachyon:pay?pk=\(pk)&amount=\(amount)"
    }

    public static func encapsulatedPayment(noteHex: String) -> String {
        "tachyon:claim?note=\(noteHex)"
    }

    public static func relayURL(relayId: String) -> String {
        "\(MockData.relayBaseURL)/pay/\(relayId)"
    }
}

// MARK: - Mock Data Constants

public enum MockData {
    public static let recipientKey = MockPaymentKey(
        label: "Recipient",
        hex: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
    )

    public static let senderKey = MockPaymentKey(
        label: "Sender",
        hex: "f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5"
    )

    public static let relayBaseURL = "https://relay.tachyon.network"
    public static let relayId = "pmt_7f3a2b1c"

    public static let mockBalance = "12.5"
    public static let mockFee = "0.0001"

    public static let mockNoteHex = "e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6"

    public static func mockReceivedPayments(primaryAmount: String = "1.0") -> [MockPayment] {
        [
            MockPayment(
                id: UUID(),
                amount: primaryAmount,
                timestamp: Date().addingTimeInterval(-60),
                senderLabel: "Anonymous",
                viaRelay: true
            ),
            MockPayment(
                id: UUID(),
                amount: "0.75",
                timestamp: Date().addingTimeInterval(-7200),
                senderLabel: "Anonymous",
                viaRelay: true
            ),
            MockPayment(
                id: UUID(),
                amount: "5.0",
                timestamp: Date().addingTimeInterval(-14400),
                senderLabel: "Anonymous",
                viaRelay: true
            )
        ]
    }
}
