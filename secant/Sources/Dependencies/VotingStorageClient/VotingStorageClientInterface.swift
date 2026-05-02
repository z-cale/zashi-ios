import ComposableArchitecture
import Foundation

extension DependencyValues {
    var votingStorage: VotingStorageClient {
        get { self[VotingStorageClient.self] }
        set { self[VotingStorageClient.self] = newValue }
    }
}

struct VotingCompletionRecord: Codable, Equatable, Sendable {
    let votedAt: Date
    let votingWeight: UInt64
    let proposalCount: Int
}

@DependencyClient
struct VotingStorageClient {
    var storeHotkey: @Sendable (_ roundId: Data, _ hotkey: VotingHotkey) async throws -> Void
    var loadHotkey: @Sendable (_ roundId: Data) async -> VotingHotkey?
    var storeDelegation: @Sendable (_ roundId: Data, _ registration: DelegationRegistration) async throws -> Void
    var loadDelegation: @Sendable (_ roundId: Data) async -> DelegationRegistration?
    var storeSession: @Sendable (_ session: VotingSession) async throws -> Void
    var loadSession: @Sendable (_ roundId: Data) async -> VotingSession?
    var clearRound: @Sendable (_ roundId: Data) async -> Void
    var storeDraftVotes: @Sendable (_ walletId: String, _ roundId: String, _ drafts: [UInt32: VoteChoice]) throws -> Void = { _, _, _ in }
    var loadDraftVotes: @Sendable (_ walletId: String, _ roundId: String) throws -> [UInt32: VoteChoice] = { _, _ in [:] }
    var clearDraftVotes: @Sendable (_ walletId: String, _ roundId: String) throws -> Void = { _, _ in }
    var storeCompletedVoteRecord: @Sendable (_ walletId: String, _ roundId: String, _ record: VotingCompletionRecord) throws -> Void = { _, _, _ in }
    var loadCompletedVoteRecord: @Sendable (_ walletId: String, _ roundId: String) throws -> VotingCompletionRecord? = { _, _ in nil }
    var loadCompletedVoteRecords: @Sendable (_ walletId: String, _ roundIds: [String]) throws -> [String: VotingCompletionRecord] = { _, _ in [:] }
    var clearCompletedVoteRecord: @Sendable (_ walletId: String, _ roundId: String) throws -> Void = { _, _ in }
    var clearPersistentState: @Sendable () throws -> Void = {}
}
