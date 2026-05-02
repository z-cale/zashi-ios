import Foundation
import ComposableArchitecture

// MARK: - Draft Persistence

extension Voting {
    /// Persisted record of when a round's vote submission fully completed,
    /// the voting weight at that moment, and how many proposals were included.
    /// Survives app termination so the Results screen can render
    /// "Voted Feb 15 - Voting Power X.XXX ZEC" and the polls list can show the
    /// "X of Y voted" indicator days after submission, even though the live
    /// session state is per-session.
    func loadCompletedVoteRecord(walletId: String, roundId: String) -> VoteRecord? {
        do {
            return try votingStorage.loadCompletedVoteRecord(walletId, roundId)
        } catch {
            votingLogger.error("Failed to load completed vote record: \(error)")
            return nil
        }
    }

    func loadCompletedVoteRecords(walletId: String, roundIds: [String]) -> [String: VoteRecord] {
        do {
            return try votingStorage.loadCompletedVoteRecords(walletId, roundIds)
        } catch {
            votingLogger.error("Failed to load completed vote records: \(error)")
            return [:]
        }
    }

    func loadDrafts(walletId: String, roundId: String) -> [UInt32: VoteChoice] {
        do {
            return try votingStorage.loadDraftVotes(walletId, roundId)
        } catch {
            votingLogger.error("Failed to load draft votes: \(error)")
            return [:]
        }
    }

    func persistDraftsEffect(_ drafts: [UInt32: VoteChoice], walletId: String, roundId: String) -> Effect<Action> {
        .run { [votingStorage] _ in
            try votingStorage.storeDraftVotes(walletId, roundId, drafts)
        } catch: { error, _ in
            votingLogger.error("Failed to persist draft votes: \(error)")
        }
    }

    func clearPersistedDraftsEffect(walletId: String, roundId: String) -> Effect<Action> {
        .run { [votingStorage] _ in
            try votingStorage.clearDraftVotes(walletId, roundId)
        } catch: { error, _ in
            votingLogger.error("Failed to clear draft votes: \(error)")
        }
    }

    func completeVoteRoundEffect(_ record: VoteRecord, walletId: String, roundId: String) -> Effect<Action> {
        .run { [votingStorage] _ in
            try votingStorage.storeCompletedVoteRecord(walletId, roundId, record)
            try votingStorage.clearDraftVotes(walletId, roundId)
        } catch: { error, _ in
            votingLogger.error("Failed to persist completed voting round: \(error)")
        }
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
