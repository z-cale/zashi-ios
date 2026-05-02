import Foundation
import ComposableArchitecture

// MARK: - Draft Persistence

extension Voting {
    private static let draftPrefix = "voting.draftVotes."
    private static let voteRecordPrefix = "voting.voteRecord."

    struct LegacyDraftEntry: Equatable {
        let key: String
        let walletId: String
        let roundId: String
        let drafts: [UInt32: VoteChoice]
    }

    /// Persisted record of when a round's vote submission fully completed,
    /// the voting weight at that moment, and how many proposals were included.
    /// Survives app termination so the Results screen can render
    /// "Voted Feb 15 - Voting Power X.XXX ZEC" and the polls list can show the
    /// "X of Y voted" indicator days after submission, even though the live
    /// session state is per-session.
    struct VoteRecord: Equatable {
        let votedAt: Date
        let votingWeight: UInt64
        let proposalCount: Int

        init(votedAt: Date, votingWeight: UInt64, proposalCount: Int) {
            self.votedAt = votedAt
            self.votingWeight = votingWeight
            self.proposalCount = proposalCount
        }
    }

    private static func voteRecordKey(walletId: String, roundId: String) -> String {
        "\(voteRecordPrefix)\(walletId)|\(roundId)"
    }

    static func persistVoteRecord(_ record: VoteRecord, walletId: String, roundId: String) {
        let key = voteRecordKey(walletId: walletId, roundId: roundId)
        UserDefaults.standard.set(
            [
                "votedAt": record.votedAt.timeIntervalSince1970,
                "votingWeight": NSNumber(value: record.votingWeight),
                "proposalCount": NSNumber(value: record.proposalCount)
            ],
            forKey: key
        )
    }

    static func loadVoteRecord(walletId: String, roundId: String) -> VoteRecord? {
        let key = voteRecordKey(walletId: walletId, roundId: roundId)
        guard let raw = UserDefaults.standard.dictionary(forKey: key),
              let votedAtUnix = raw["votedAt"] as? Double,
              let weight = (raw["votingWeight"] as? NSNumber)?.uint64Value else {
            return nil
        }
        // proposalCount was added later — older records default to 0 and the
        // view falls back to the round's full proposal count for display.
        let count = (raw["proposalCount"] as? NSNumber)?.intValue ?? 0
        return VoteRecord(
            votedAt: Date(timeIntervalSince1970: votedAtUnix),
            votingWeight: weight,
            proposalCount: count
        )
    }

    static func clearPersistedVoteRecord(walletId: String, roundId: String) {
        UserDefaults.standard.removeObject(forKey: voteRecordKey(walletId: walletId, roundId: roundId))
    }

    /// A round-level vote record is only valid once all drafts are gone.
    /// Older builds wrote it too early, so clear it if there is still
    /// outstanding editable work for the round.
    static func loadCompletedVoteRecord(walletId: String, roundId: String, hasDrafts: Bool) -> VoteRecord? {
        guard !hasDrafts else {
            clearPersistedVoteRecord(walletId: walletId, roundId: roundId)
            return nil
        }
        return loadVoteRecord(walletId: walletId, roundId: roundId)
    }

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

    static func legacyDraftEntries(userDefaults: UserDefaults = .standard) -> [LegacyDraftEntry] {
        userDefaults.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix(draftPrefix) else { return nil }
            let suffix = key.dropFirst(draftPrefix.count)
            guard let separator = suffix.firstIndex(of: "|") else { return nil }
            let walletId = String(suffix[..<separator])
            let roundStart = suffix.index(after: separator)
            let roundId = String(suffix[roundStart...])
            guard !walletId.isEmpty, !roundId.isEmpty else { return nil }
            guard let drafts = decodeLegacyDrafts(value), !drafts.isEmpty else { return nil }
            return LegacyDraftEntry(key: key, walletId: walletId, roundId: roundId, drafts: drafts)
        }
        .sorted { lhs, rhs in
            if lhs.walletId != rhs.walletId { return lhs.walletId < rhs.walletId }
            if lhs.roundId != rhs.roundId { return lhs.roundId < rhs.roundId }
            return lhs.key < rhs.key
        }
    }

    static func migrateLegacyDrafts(votingCrypto: VotingCryptoClient, activeWalletId: String) async throws {
        let entries = legacyDraftEntries()
        guard !entries.isEmpty else { return }

        do {
            for entry in entries {
                try await votingCrypto.setWalletId(entry.walletId)
                try await votingCrypto.replaceDraftVotes(entry.roundId, draftRecords(from: entry.drafts))
                UserDefaults.standard.removeObject(forKey: entry.key)
            }
            try await votingCrypto.setWalletId(activeWalletId)
            votingLogger.info("Migrated \(entries.count) legacy voting draft sets")
        } catch {
            try? await votingCrypto.setWalletId(activeWalletId)
            throw error
        }
    }

    static func clearLegacyDraftKeys(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(draftPrefix) {
            userDefaults.removeObject(forKey: key)
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

    private static func decodeLegacyDrafts(_ value: Any) -> [UInt32: VoteChoice]? {
        guard let raw = value as? [String: Any] else { return nil }
        var drafts: [UInt32: VoteChoice] = [:]
        for (proposalKey, choiceValue) in raw {
            guard
                let proposalId = UInt32(proposalKey),
                let choiceIndex = legacyChoiceIndex(from: choiceValue)
            else {
                return nil
            }
            drafts[proposalId] = .option(choiceIndex)
        }
        return drafts
    }

    private static func legacyChoiceIndex(from value: Any) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt32(exactly: value)
        }
        if let value = value as? UInt, value <= UInt(UInt32.max) {
            return UInt32(value)
        }
        if let value = value as? NSNumber {
            let uintValue = value.uint64Value
            guard uintValue <= UInt64(UInt32.max) else { return nil }
            return UInt32(uintValue)
        }
        if let value = value as? String {
            return UInt32(value)
        }
        return nil
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
