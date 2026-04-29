import XCTest
import ComposableArchitecture
@testable import secant_testnet

// Test fixtures contain pinned canonical JSON strings that intentionally exceed
// the project's line-length limit — keeping them single-line makes the expected
// byte output obvious and prevents accidental line-ending differences from
// changing the pinned hash.
// swiftlint:disable line_length

final class VotingServiceConfigTests: XCTestCase {

    // MARK: - Canonical JSON (ZIP 1244 §"Proposals Hash")

    /// ZIP 1244 worked example.
    private static let zipExampleProposal = VotingServiceConfig.Proposal(
        id: 1,
        title: "Approve protocol upgrade",
        description: "Approve or oppose the proposed protocol upgrade.",
        options: [
            .init(index: 0, label: "Support"),
            .init(index: 1, label: "Oppose"),
        ]
    )
    private static let zipExampleCanonical =
        #"[{"id":1,"title":"Approve protocol upgrade","description":"Approve or oppose the proposed protocol upgrade.","options":[{"index":0,"label":"Support"},{"index":1,"label":"Oppose"}]}]"#
    /// SHA-256 of the above canonical string, computed with `shasum -a 256` for reference.
    private static let zipExampleHashHex = "3f9a361d43c4ddb77ad138a091374e2e2958718e64937f33df99a09bd567e63d"

    func testCanonicalJSONMatchesZIPExample() {
        let canonical = VotingServiceConfig.canonicalProposalsJSON([Self.zipExampleProposal])
        XCTAssertEqual(canonical, Self.zipExampleCanonical)
    }

    func testComputeProposalsHashMatchesZIPExample() {
        let data = VotingServiceConfig.computeProposalsHash([Self.zipExampleProposal])
        let hex = data.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, Self.zipExampleHashHex)
    }

    func testCanonicalJSONSortsProposalsByIdAndOptionsByIndex() {
        let unsorted = [
            VotingServiceConfig.Proposal(
                id: 2,
                title: "B",
                description: "second",
                options: [.init(index: 1, label: "No"), .init(index: 0, label: "Yes")]
            ),
            VotingServiceConfig.Proposal(
                id: 1,
                title: "A",
                description: "first",
                options: [.init(index: 0, label: "X"), .init(index: 1, label: "Y")]
            ),
        ]
        let canonical = VotingServiceConfig.canonicalProposalsJSON(unsorted)
        XCTAssertEqual(
            canonical,
            #"[{"id":1,"title":"A","description":"first","options":[{"index":0,"label":"X"},{"index":1,"label":"Y"}]},{"id":2,"title":"B","description":"second","options":[{"index":0,"label":"Yes"},{"index":1,"label":"No"}]}]"#
        )
    }

    func testCanonicalJSONEscapesSpecialCharactersInStrings() {
        let proposal = VotingServiceConfig.Proposal(
            id: 1,
            title: "Quote \" and backslash \\",
            description: "tab\there",
            options: [.init(index: 0, label: "tab\there")]
        )
        let canonical = VotingServiceConfig.canonicalProposalsJSON([proposal])
        XCTAssertTrue(canonical.contains(#"\""#), "should escape double quotes")
        XCTAssertTrue(canonical.contains(#"\\"#), "should escape backslashes")
        XCTAssertTrue(canonical.contains(#"\t"#), "should escape tabs")
    }

    /// Pins the canonicalization to Rust `serde_json::to_string` byte output for a
    /// title containing `/`. Swift's `JSONSerialization` default would emit `\/`; Rust
    /// emits `/`. A mismatch here would cause every wallet to hard-fail `proposalsHashMismatch`
    /// against the chain's `proposals_hash` for any round with a slash in a title or label.
    /// The reference hash is computed from: `shasum -a 256` of the serde_json form below.
    func testCanonicalJSONDoesNotEscapeForwardSlashInTitles() {
        let proposal = VotingServiceConfig.Proposal(
            id: 1,
            title: "NU5/NU6 activation",
            description: "Should we activate NU5/NU6?",
            options: [
                .init(index: 0, label: "Yes"),
                .init(index: 1, label: "No"),
            ]
        )
        let canonical = VotingServiceConfig.canonicalProposalsJSON([proposal])
        XCTAssertEqual(
            canonical,
            #"[{"id":1,"title":"NU5/NU6 activation","description":"Should we activate NU5/NU6?","options":[{"index":0,"label":"Yes"},{"index":1,"label":"No"}]}]"#
        )
        let hex = VotingServiceConfig.computeProposalsHash([proposal])
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "d4a105be1f44c96ca4abc6c952d7a6deb3f7cf4df2059a2afe4bb828b96078a1")
    }

    // MARK: - Decode regression for post-Part-E CDN JSON

    func testDecodeFromFullZIP1244CompliantJSON() throws {
        let json = """
        {
          "config_version": 1,
          "vote_round_id": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
          "vote_servers": [
            {"url": "https://vote1.example.com", "label": "validator-1"}
          ],
          "pir_endpoints": [
            {"url": "https://pir1.example.com", "label": "pir-1"}
          ],
          "snapshot_height": 2800000,
          "vote_end_time": 1735689600,
          "proposals": [
            {
              "id": 1,
              "title": "Approve protocol upgrade",
              "description": "Approve or oppose the proposed protocol upgrade.",
              "options": [
                {"index": 0, "label": "Support"},
                {"index": 1, "label": "Oppose"}
              ]
            }
          ],
          "supported_versions": {
            "pir": ["v0", "v1"],
            "vote_protocol": "v0",
            "tally": "v0",
            "vote_server": "v1"
          }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(VotingServiceConfig.self, from: data)

        XCTAssertEqual(config.configVersion, 1)
        XCTAssertEqual(config.voteRoundId, "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899")
        XCTAssertEqual(config.voteServers.count, 1)
        XCTAssertEqual(config.pirEndpoints.first?.label, "pir-1")
        XCTAssertEqual(config.snapshotHeight, 2_800_000)
        XCTAssertEqual(config.voteEndTime, 1_735_689_600)
        XCTAssertEqual(config.proposals.count, 1)
        XCTAssertEqual(config.proposals[0].options.count, 2)
        XCTAssertEqual(config.supportedVersions.voteServer, "v1")
        XCTAssertEqual(config.supportedVersions.pir, ["v0", "v1"])
    }

    func testDecodeFailsWhenRequiredFieldMissing() {
        let jsonMissingProposals = """
        {
          "config_version": 1,
          "vote_round_id": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
          "vote_servers": [{"url": "https://x", "label": "a"}],
          "pir_endpoints": [{"url": "https://y", "label": "b"}],
          "snapshot_height": 1,
          "vote_end_time": 1,
          "supported_versions": {"pir": ["v0"], "vote_protocol": "v0", "tally": "v0", "vote_server": "v1"}
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(VotingServiceConfig.self, from: Data(jsonMissingProposals.utf8))
        )
    }

    // MARK: - validate() — supported_versions enforcement

    private func makeConfig(supportedVersions: VotingServiceConfig.SupportedVersions) -> VotingServiceConfig {
        VotingServiceConfig(
            configVersion: 1,
            voteRoundId: String(repeating: "a", count: 64),
            voteServers: [.init(url: "https://x", label: "a")],
            pirEndpoints: [.init(url: "https://y", label: "b")],
            snapshotHeight: 1,
            voteEndTime: 1,
            proposals: [Self.zipExampleProposal],
            supportedVersions: supportedVersions
        )
    }

    func testValidateAcceptsCurrentWalletCapabilities() throws {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsUnknownVoteServer() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v99")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, let advertised) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "vote_server")
            XCTAssertEqual(advertised, "v99")
        }
    }

    func testValidateRejectsWhenPIRIntersectionIsEmpty() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v42"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "pir")
        }
    }

    func testValidateAcceptsWhenPIRIntersectionIsNonEmpty() throws {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v42", "v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsUnknownVoteProtocol() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v99", tally: "v0", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "vote_protocol")
        }
    }

    func testValidateRejectsUnknownTally() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v99", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "tally")
        }
    }
}

private actor SharePostRecorder {
    private var postedServers: [String] = []

    func record(_ server: String) {
        postedServers.append(server)
    }

    func servers() -> [String] {
        postedServers
    }
}

private struct SharePostFailure: Error {}

private actor VoteSubmissionRecorder {
    private var submittedProposalIds: [UInt32] = []

    func recordSubmittedProposal(_ proposalId: UInt32) {
        submittedProposalIds.append(proposalId)
    }

    func submittedProposals() -> [UInt32] {
        submittedProposalIds
    }
}

private actor CommitmentBundleStoreRecorder {
    private var vcTreePositions: [UInt64] = []

    func record(vcTreePosition: UInt64) {
        vcTreePositions.append(vcTreePosition)
    }

    func positions() -> [UInt64] {
        vcTreePositions
    }
}

@MainActor
final class VotingSubmissionPostFallbackTests: XCTestCase {
    func testDraftMutationIsIgnoredAfterVoteRecordIsPersisted() async {
        let round = Self.makeVotingRound()
        var initialState = Voting.State(
            votingRound: round,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            walletId: "wallet-id",
            roundId: "aabb"
        )
        initialState.activeSession = Self.makeVotingSession(proposals: round.proposals)
        initialState.serviceConfig = Self.makeServiceConfig()
        initialState.bundleCount = 1
        initialState.delegationProofStatus = .complete
        initialState.draftVotes = [1: .option(0)]
        initialState.voteRecord = Voting.VoteRecord(
            votedAt: Date(timeIntervalSince1970: 1),
            votingWeight: 100_000_000,
            proposalCount: 1
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }

        await store.send(.setDraftVote(proposalId: 1, choice: .option(1)))
        await store.send(.clearDraftVote(proposalId: 1))
    }

    func testLockedPendingDraftCanStillRetrySubmission() {
        let round = Self.makeVotingRound()
        var state = Voting.State(
            votingRound: round,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            walletId: "wallet-id",
            roundId: "aabb"
        )
        state.bundleCount = 1
        state.draftVotes = [1: .option(0)]
        state.voteRecord = Voting.VoteRecord(
            votedAt: Date(timeIntervalSince1970: 1),
            votingWeight: 100_000_000,
            proposalCount: 1
        )

        XCTAssertTrue(state.canSubmitBatch)
    }

    func testShareServerExhaustionStopsBeforeSubmittingLaterDrafts() async {
        let round = Self.makeVotingRound(proposalCount: 2)
        let walletId = "wallet-\(UUID().uuidString)"
        let roundId = "aabb"
        var initialState = Voting.State(
            votingRound: round,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            walletId: walletId,
            roundId: roundId
        )
        initialState.activeSession = Self.makeVotingSession(proposals: round.proposals)
        initialState.serviceConfig = Self.makeServiceConfig()
        initialState.bundleCount = 1
        initialState.delegationProofStatus = .complete
        initialState.draftVotes = [1: .option(0), 2: .option(0)]

        let recorder = VoteSubmissionRecorder()
        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off
        store.dependencies.backgroundTask = .noOp
        store.dependencies.mnemonic = .noOp
        store.dependencies.walletStorage = .noOp

        var votingAPI = VotingAPIClient()
        votingAPI.submitVoteCommitment = { bundle, _ in
            await recorder.recordSubmittedProposal(bundle.proposalId)
            return TxResult(txHash: "tx-\(bundle.proposalId)", code: 0)
        }
        votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(
                height: 1,
                code: 0,
                events: [
                    TxEvent(
                        type: "cast_vote",
                        attributes: [.init(key: "leaf_index", value: "0,0")]
                    )
                ]
            )
        }
        votingAPI.delegateShares = { _, _, _ in
            throw VotingFlowError.noReachableVoteServers
        }
        store.dependencies.votingAPI = votingAPI

        var votingCrypto = VotingCryptoClient()
        votingCrypto.getVotes = { _ in [] }
        votingCrypto.getVoteTxHash = { _, _, _ in throw SharePostFailure() }
        votingCrypto.syncVoteTree = { _, _ in 1 }
        votingCrypto.generateVanWitness = { _, _, anchorHeight in
            VanWitness(authPath: [], position: 0, anchorHeight: anchorHeight)
        }
        votingCrypto.buildVoteCommitment = {
            roundId, _, _, _, proposalId, _, _, _, _, anchorHeight, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.completed(
                    Self.makeVoteCommitmentBundle(
                        proposalId: proposalId,
                        roundId: roundId,
                        anchorHeight: anchorHeight
                    )
                ))
                continuation.finish()
            }
        }
        votingCrypto.storeVoteCommitmentBundle = { _, _, _, _, _ in }
        votingCrypto.signCastVote = { _, _, _ in CastVoteSignature(voteAuthSig: Data([0x01])) }
        votingCrypto.storeVoteTxHash = { _, _, _, _ in }
        votingCrypto.storeVanPosition = { _, _, _ in }
        votingCrypto.buildSharePayloads = { _, bundle, choice, _, treePosition, _ in
            [Self.makeSharePayload(
                proposalId: bundle.proposalId,
                voteDecision: choice.index,
                treePosition: treePosition
            )]
        }
        votingCrypto.computeShareNullifier = { _, _, _ in String(repeating: "00", count: 32) }
        votingCrypto.recordShareDelegation = { _, _, _, _, _, _, _ in }
        votingCrypto.markVoteSubmitted = { _, _, _ in }
        store.dependencies.votingCrypto = votingCrypto

        await store.send(.authenticationSucceeded)
        await store.finish()
        await store.skipReceivedActions()

        let submittedProposals = await recorder.submittedProposals()
        XCTAssertEqual(submittedProposals, [1])
        XCTAssertEqual(store.state.draftVotes, [1: .option(0), 2: .option(0)])
        XCTAssertEqual(store.state.batchVoteErrors.keys.sorted(), [1])
        guard case let .submissionFailed(_, submittedCount, totalCount) = store.state.batchSubmissionStatus,
              submittedCount == 0,
              totalCount == 1
        else {
            return XCTFail("Expected submission failure for only the attempted proposal")
        }
    }

    func testRecoveredVoteCommitmentPersistsConfirmedVcTreePositionBeforeShareDelegation() async {
        let round = Self.makeVotingRound()
        var initialState = Voting.State(
            votingRound: round,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            walletId: "wallet-id",
            roundId: "aabb"
        )
        initialState.activeSession = Self.makeVotingSession(proposals: round.proposals)
        initialState.serviceConfig = Self.makeServiceConfig()
        initialState.bundleCount = 1
        initialState.delegationProofStatus = .complete
        initialState.draftVotes = [1: .option(0)]

        let recorder = CommitmentBundleStoreRecorder()
        let submittedRecorder = VoteSubmissionRecorder()
        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off
        store.dependencies.backgroundTask = .noOp
        store.dependencies.mnemonic = .noOp
        store.dependencies.walletStorage = .noOp

        var votingAPI = VotingAPIClient()
        votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(
                height: 1,
                code: 0,
                events: [
                    TxEvent(
                        type: "cast_vote",
                        attributes: [.init(key: "leaf_index", value: "0,42")]
                    )
                ]
            )
        }
        votingAPI.submitVoteCommitment = { bundle, _ in
            await submittedRecorder.recordSubmittedProposal(bundle.proposalId)
            return TxResult(txHash: "unexpected", code: 0)
        }
        votingAPI.delegateShares = { payloads, _, serverURLs in
            ShareDelegationResult(
                delegatedShares: payloads.map {
                    DelegatedShareInfo(
                        shareIndex: $0.encShare.shareIndex,
                        proposalId: $0.proposalId,
                        acceptedByServers: [serverURLs[0]]
                    )
                },
                remainingServerURLs: serverURLs
            )
        }
        store.dependencies.votingAPI = votingAPI

        var votingCrypto = VotingCryptoClient()
        votingCrypto.getVotes = { _ in [] }
        votingCrypto.getVoteTxHash = { _, _, _ in .present("cached-tx") }
        votingCrypto.storeVanPosition = { _, _, _ in }
        votingCrypto.getVoteCommitmentBundle = { roundId, _, proposalId in
            Self.makeVoteCommitmentBundle(
                proposalId: proposalId,
                roundId: roundId,
                anchorHeight: 1
            )
        }
        votingCrypto.storeVoteCommitmentBundle = { _, _, _, _, vcTreePosition in
            await recorder.record(vcTreePosition: vcTreePosition)
        }
        votingCrypto.buildSharePayloads = { _, bundle, choice, _, treePosition, _ in
            [Self.makeSharePayload(
                proposalId: bundle.proposalId,
                voteDecision: choice.index,
                treePosition: treePosition
            )]
        }
        votingCrypto.computeShareNullifier = { _, _, _ in String(repeating: "00", count: 32) }
        votingCrypto.recordShareDelegation = { _, _, _, _, _, _, _ in }
        votingCrypto.markVoteSubmitted = { _, _, _ in }
        store.dependencies.votingCrypto = votingCrypto

        await store.send(.authenticationSucceeded)
        await store.finish()
        await store.skipReceivedActions()

        let storedPositions = await recorder.positions()
        let submittedProposals = await submittedRecorder.submittedProposals()
        XCTAssertEqual(storedPositions, [42])
        XCTAssertEqual(submittedProposals, [])
    }

    private static func makeVotingRound(proposalCount: Int = 1) -> VotingRound {
        VotingRound(
            id: "aabb",
            title: "Round",
            description: "Round description",
            snapshotHeight: 1,
            snapshotDate: Date(timeIntervalSince1970: 1),
            votingStart: Date(timeIntervalSince1970: 2),
            votingEnd: Date(timeIntervalSince1970: 3),
            proposals: (1...proposalCount).map { id in
                VotingProposal(
                    id: UInt32(id),
                    title: "Proposal \(id)",
                    description: "Proposal description",
                    options: [
                        .init(index: 0, label: "Yes"),
                        .init(index: 1, label: "No")
                    ]
                )
            }
        )
    }

    nonisolated private static func makeVoteCommitmentBundle(
        proposalId: UInt32,
        roundId: String,
        anchorHeight: UInt32
    ) -> VoteCommitmentBundle {
        let share = EncryptedShare(
            c1: Data(repeating: 0x01, count: 32),
            c2: Data(repeating: 0x02, count: 32),
            shareIndex: 0
        )
        return VoteCommitmentBundle(
            vanNullifier: Data(repeating: 0x03, count: 32),
            voteAuthorityNoteNew: Data(repeating: 0x04, count: 32),
            voteCommitment: Data(repeating: 0x05, count: 32),
            proposalId: proposalId,
            proof: Data(repeating: 0x06, count: 32),
            encShares: [share],
            anchorHeight: anchorHeight,
            voteRoundId: roundId,
            sharesHash: Data(repeating: 0x07, count: 32),
            shareBlindFactors: [Data(repeating: 0x08, count: 32)],
            shareComms: [Data(repeating: 0x09, count: 32)],
            rVpkBytes: Data(repeating: 0x0A, count: 32),
            alphaV: Data(repeating: 0x0B, count: 32)
        )
    }

    nonisolated private static func makeSharePayload(
        proposalId: UInt32,
        voteDecision: UInt32,
        treePosition: UInt64
    ) -> SharePayload {
        let share = EncryptedShare(
            c1: Data(repeating: 0x01, count: 32),
            c2: Data(repeating: 0x02, count: 32),
            shareIndex: 0
        )
        return SharePayload(
            sharesHash: Data(repeating: 0x03, count: 32),
            proposalId: proposalId,
            voteDecision: voteDecision,
            encShare: share,
            treePosition: treePosition,
            allEncShares: [share],
            shareComms: [Data(repeating: 0x04, count: 32)],
            primaryBlind: Data(repeating: 0x05, count: 32),
            submitAt: 0
        )
    }

    private static func makeVotingSession(proposals: [VotingProposal]) -> VotingSession {
        VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 1,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(timeIntervalSince1970: 3),
            ceremonyStart: Date(timeIntervalSince1970: 2),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: proposals,
            status: .active
        )
    }

    private static func makeServiceConfig() -> VotingServiceConfig {
        VotingServiceConfig(
            configVersion: 1,
            voteRoundId: String(repeating: "a", count: 64),
            voteServers: [.init(url: "https://vote.example.com", label: "vote")],
            pirEndpoints: [.init(url: "https://pir.example.com", label: "pir")],
            snapshotHeight: 1,
            voteEndTime: 3,
            proposals: [],
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
    }
}

final class ShareDelegationPostFallbackTests: XCTestCase {
    func testShareDelegationUsesSingleConfiguredServer() async throws {
        let recorder = SharePostRecorder()
        let payloads = (0..<5).map { Self.makePayload(index: UInt32($0)) }

        let result = try await delegateSharePayloads(
            payloads,
            roundIdHex: "aabb",
            initialServerURLs: ["https://online.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
            }
        )

        let postedServers = await recorder.servers()
        XCTAssertEqual(postedServers, Array(repeating: "https://online.example.com", count: 5))
        XCTAssertEqual(result.remainingServerURLs, ["https://online.example.com"])
    }

    func testShareDelegationRemovesFailedServerForRemainingShares() async throws {
        let recorder = SharePostRecorder()
        let payloads = (0..<2).map { Self.makePayload(index: UInt32($0)) }

        let result = try await delegateSharePayloads(
            payloads,
            roundIdHex: "aabb",
            initialServerURLs: ["https://offline.example.com", "https://online.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
                if server == "https://offline.example.com" {
                    throw SharePostFailure()
                }
            },
            selectTargets: { servers, quorum in Array(servers.prefix(quorum)) }
        )

        let postedServers = await recorder.servers()
        XCTAssertEqual(
            postedServers,
            ["https://offline.example.com", "https://online.example.com", "https://online.example.com"]
        )
        XCTAssertEqual(result.remainingServerURLs, ["https://online.example.com"])
    }

    func testShareDelegationAllServersFailThrowsNoReachableError() async throws {
        let payloads = [Self.makePayload(index: 0)]

        do {
            _ = try await delegateSharePayloads(
                payloads,
                roundIdHex: "aabb",
                initialServerURLs: ["https://offline-one.example.com", "https://offline-two.example.com"],
                postShare: { _, _ in throw SharePostFailure() },
                selectTargets: { servers, quorum in Array(servers.prefix(quorum)) }
            )
            XCTFail("Expected share delegation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Unable to reach any vote server. Please check your internet connection and try again."
            )
        }
    }

    func testResubmissionCandidatesExcludePreviouslySentServersFirst() {
        let candidates = resubmissionCandidateServers(
            allServerURLs: [
                "https://vote-a.example.com",
                "https://vote-b.example.com",
                "https://vote-c.example.com"
            ],
            excludeURLs: [
                "https://vote-a.example.com",
                "https://vote-c.example.com"
            ]
        )

        XCTAssertEqual(candidates, ["https://vote-b.example.com"])
    }

    func testResubmissionCandidatesFallBackToAllConfiguredServersWhenAllWereTried() {
        let allServers = [
            "https://vote-a.example.com",
            "https://vote-b.example.com"
        ]

        let candidates = resubmissionCandidateServers(
            allServerURLs: allServers,
            excludeURLs: allServers
        )

        XCTAssertEqual(candidates, allServers)
    }

    func testResubmissionFallsBackToPreviouslySentServerWhenUntriedServerFails() async {
        let recorder = SharePostRecorder()
        let payload = Self.makePayload(index: 0)

        let acceptedServers = await resubmitSharePayload(
            payload,
            roundIdHex: "aabb",
            allServerURLs: [
                "https://already-sent.example.com",
                "https://offline-untried.example.com"
            ],
            excludeURLs: ["https://already-sent.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
                if server == "https://offline-untried.example.com" {
                    throw SharePostFailure()
                }
            },
            selectTargets: { servers, quorum in Array(servers.prefix(quorum)) }
        )

        let postedServers = await recorder.servers()
        XCTAssertEqual(postedServers, ["https://offline-untried.example.com", "https://already-sent.example.com"])
        XCTAssertEqual(acceptedServers, ["https://already-sent.example.com"])
    }

    func testShareStatusLookupFallsThroughOfflineFirstHelper() async {
        let recorder = SharePostRecorder()

        let result = await fetchShareStatusFromAvailableHelpers(
            serverURLs: ["https://offline.example.com", "https://online.example.com"],
            roundIdHex: "aabb",
            nullifierHex: String(repeating: "00", count: 32),
            fetchShareStatus: { server, _, _ in
                await recorder.record(server)
                if server == "https://offline.example.com" {
                    throw SharePostFailure()
                }
                return .pending
            }
        )

        let postedServers = await recorder.servers()
        XCTAssertEqual(postedServers, ["https://offline.example.com", "https://online.example.com"])
        XCTAssertEqual(result.confirmation, .pending)
        XCTAssertEqual(result.remainingServerURLs, ["https://online.example.com"])
    }

    func testShareStatusLookupPrunesAllFailedHelpers() async {
        let recorder = SharePostRecorder()

        let result = await fetchShareStatusFromAvailableHelpers(
            serverURLs: ["https://offline-one.example.com", "https://offline-two.example.com"],
            roundIdHex: "aabb",
            nullifierHex: String(repeating: "00", count: 32),
            fetchShareStatus: { server, _, _ in
                await recorder.record(server)
                throw SharePostFailure()
            }
        )

        let postedServers = await recorder.servers()
        XCTAssertEqual(postedServers, ["https://offline-one.example.com", "https://offline-two.example.com"])
        XCTAssertNil(result.confirmation)
        XCTAssertEqual(result.remainingServerURLs, [])
    }

    func testOverdueShareCanResubmitWhenStatusIsUnavailable() {
        XCTAssertTrue(shouldResubmitShare(submitAt: 100, createdAt: 50, now: 140, voteEndTime: 200))
        XCTAssertFalse(shouldResubmitShare(submitAt: 100, createdAt: 50, now: 110, voteEndTime: 200))
        XCTAssertFalse(shouldResubmitShare(submitAt: 100, createdAt: 50, now: 195, voteEndTime: 200))
    }

    func testImmediateShareCanResubmitFromCreatedAtWhenStatusIsUnavailable() {
        XCTAssertTrue(shouldResubmitShare(submitAt: 0, createdAt: 100, now: 140, voteEndTime: 200))
        XCTAssertFalse(shouldResubmitShare(submitAt: 0, createdAt: 100, now: 120, voteEndTime: 200))
        XCTAssertFalse(shouldResubmitShare(submitAt: 0, createdAt: 100, now: 195, voteEndTime: 200))
        XCTAssertFalse(shouldResubmitShare(submitAt: 0, createdAt: 0, now: 140, voteEndTime: 200))
    }

    private static func makePayload(index: UInt32) -> SharePayload {
        let share = EncryptedShare(
            c1: Data(repeating: UInt8(index + 1), count: 32),
            c2: Data(repeating: UInt8(index + 2), count: 32),
            shareIndex: index
        )
        return SharePayload(
            sharesHash: Data(repeating: 0x01, count: 32),
            proposalId: 1,
            voteDecision: 0,
            encShare: share,
            treePosition: 10,
            allEncShares: [share],
            shareComms: [Data(repeating: 0x03, count: 32)],
            primaryBlind: Data(repeating: 0x04, count: 32),
            submitAt: 0
        )
    }
}
// swiftlint:enable line_length
