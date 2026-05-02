import Foundation
import ComposableArchitecture

// MARK: - Draft Persistence

extension Voting {
    static func draftRecords(from drafts: [UInt32: VoteChoice]) -> [DraftVoteRecord] {
        drafts
            .sorted { $0.key < $1.key }
            .map { DraftVoteRecord(proposalId: $0.key, choice: $0.value) }
    }

    static func draftDictionary(from records: [DraftVoteRecord]) -> [UInt32: VoteChoice] {
        records.reduce(into: [UInt32: VoteChoice]()) { dict, record in
            dict[record.proposalId] = record.choice
        }
    }

    func persistDraftsEffect(_ drafts: [UInt32: VoteChoice], roundId: String) -> Effect<Action> {
        .run { [votingCrypto] _ in
            try Task.checkCancellation()
            try await votingCrypto.replaceDraftVotes(roundId, Self.draftRecords(from: drafts))
        } catch: { error, _ in
            if !(error is CancellationError) {
                votingLogger.error("Failed to persist voting drafts: \(error)")
            }
        }
        .cancellable(id: cancelDraftPersistenceId, cancelInFlight: true)
    }

    func clearDraftsEffect(roundId: String) -> Effect<Action> {
        .run { [votingCrypto] _ in
            try Task.checkCancellation()
            try await votingCrypto.clearDraftVotes(roundId)
        } catch: { error, _ in
            if !(error is CancellationError) {
                votingLogger.error("Failed to clear voting drafts: \(error)")
            }
        }
        .cancellable(id: cancelDraftPersistenceId, cancelInFlight: true)
    }

    func completeVoteRoundEffect(_ record: CompletedVoteRecord, roundId: String) -> Effect<Action> {
        .run { [votingCrypto] _ in
            try Task.checkCancellation()
            try await votingCrypto.completeVoteRound(roundId, record)
        } catch: { error, _ in
            if !(error is CancellationError) {
                votingLogger.error("Failed to persist completed voting record: \(error)")
            }
        }
        .cancellable(id: cancelCompletionPersistenceId, cancelInFlight: true)
    }
}

// MARK: - Note Bundling

/// Result of value-aware note bundling on the Swift side.
struct BundleResult {
    let bundles: [[NoteInfo]]
    let eligibleWeight: UInt64
    let droppedCount: Int
}

extension Array where Element == NoteInfo {
    /// Value-aware bundling using greedy min-total assignment.
    ///
    /// Mirrors the Rust peer `chunk_notes` (see
    /// `zcash_voting/zcash_voting/src/types.rs` — function `chunk_notes`) for
    /// client-side use. The numbered steps in the body track that function
    /// one-to-one:
    /// 1. Sort notes by value DESC, then position ASC as tiebreaker
    /// 2. Fill bundles sequentially to capacity (5 notes each)
    /// 3. Drop bundles with total < ballotDivisor
    /// 4. Re-sort notes within each surviving bundle by position
    /// 5. Sort surviving bundles by total value DESC (min position as tiebreaker)
    func smartBundles() -> BundleResult {
        guard !isEmpty else {
            return BundleResult(bundles: [], eligibleWeight: 0, droppedCount: 0)
        }

        // Step 1: Sort by value DESC, then position ASC
        let sorted = self.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.position < rhs.position
        }

        // Step 2: Fill bundles sequentially to capacity (5 notes each)
        var bundleNotes: [[NoteInfo]] = []
        var bundleTotals: [UInt64] = []

        for note in sorted {
            if bundleNotes.isEmpty || (bundleNotes.last?.count ?? 0) >= 5 {
                bundleNotes.append([])
                bundleTotals.append(0)
            }
            let last = bundleNotes.count - 1
            bundleTotals[last] += note.value
            bundleNotes[last].append(note)
        }

        // Step 3: Drop bundles with total < ballotDivisor
        let numBundles = bundleNotes.count
        var surviving: [(total: UInt64, notes: [NoteInfo])] = []
        var eligibleWeight: UInt64 = 0
        var survivingNoteCount = 0

        for i in 0..<numBundles where bundleTotals[i] >= ballotDivisor {
            surviving.append((bundleTotals[i], bundleNotes[i]))
            eligibleWeight += quantizeWeight(bundleTotals[i])
            survivingNoteCount += bundleNotes[i].count
        }
        let droppedCount = count - survivingNoteCount

        // Step 5: Re-sort notes within each surviving bundle by position
        for i in 0..<surviving.count {
            surviving[i].notes.sort { $0.position < $1.position }
        }

        // Step 6: Sort surviving bundles by total value DESC (min position as tiebreaker).
        // This ensures bundle 0 is always the most valuable, enabling users to skip
        // low-value trailing bundles during Keystone signing.
        surviving.sort { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return (lhs.notes.first?.position ?? .max) < (rhs.notes.first?.position ?? .max)
        }

        return BundleResult(bundles: surviving.map(\.notes), eligibleWeight: eligibleWeight, droppedCount: droppedCount)
    }
}

/// Convert hex string to Data (used for share confirmation polling and API parsing).
func votingDataFromHex(_ hex: String) -> Data {
    var data = Data()
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        if let byte = UInt8(hex[idx..<next], radix: 16) {
            data.append(byte)
        }
        idx = next
    }
    return data
}

// MARK: - Skip Bundles Alert

extension AlertState where Action == Voting.Action {
    static func confirmSkip(lockedIn: String, givingUp: String) -> AlertState {
        AlertState {
            TextState(String(localizable: .coinVoteDelegationSigningSkipAlertTitle))
        } actions: {
            ButtonState(role: .destructive, action: .skipRemainingKeystoneBundlesConfirmed) {
                TextState(String(localizable: .coinVoteDelegationSigningSkipAlertPrimary))
            }
            ButtonState(role: .cancel, action: .skipBundlesAlert(.dismiss)) {
                TextState(String(localizable: .coinVoteCommonCancel))
            }
        } message: {
            TextState(String(localizable: .coinVoteDelegationSigningSkipAlertMessage(lockedIn, givingUp)))
        }
    }
}
