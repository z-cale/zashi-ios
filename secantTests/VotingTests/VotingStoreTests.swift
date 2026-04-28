import XCTest
import ComposableArchitecture
import DatabaseFiles
import MnemonicClient
import SDKSynchronizer
import Voting
import VotingCryptoClient
import VotingModels
import WalletStorage
import ZcashSDKEnvironment
@testable import secant_testnet

@MainActor
final class VotingStoreTests: XCTestCase {
    func testAllRoundsLoadedWithNormalIntentShowsPollsList() async throws {
        let sessions = [
            makeVotingSession(idByte: 0x01, status: .active, createdAtHeight: 1)
        ]
        var initialState = Voting.State(walletId: "entry-intent-normal")
        initialState.screenStack = [.loading]

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        await store.send(.allRoundsLoaded(sessions))

        XCTAssertEqual(store.state.screenStack, [.pollsList])
        XCTAssertEqual(store.state.entryIntent, .normal)
        XCTAssertNil(store.state.activeSession)
    }

    func testAllRoundsLoadedWithResultsIntentOpensNewestFinalizedRound() async throws {
        let olderFinalized = makeVotingSession(idByte: 0x01, status: .finalized, createdAtHeight: 1, title: "Older")
        let tallying = makeVotingSession(idByte: 0x02, status: .tallying, createdAtHeight: 2, title: "Tallying")
        let newestFinalized = makeVotingSession(idByte: 0x03, status: .finalized, createdAtHeight: 3, title: "Newest")
        let initialState = Voting.State(walletId: "entry-intent-newest", entryIntent: .results(roundId: nil))

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        await store.send(.allRoundsLoaded([olderFinalized, tallying, newestFinalized]))

        XCTAssertEqual(store.state.screenStack, [.results])
        XCTAssertEqual(store.state.entryIntent, .normal)
        XCTAssertEqual(store.state.roundId, roundId(for: newestFinalized))
        XCTAssertEqual(store.state.votingRound.title, "Newest")
    }

    func testAllRoundsLoadedWithResultsIntentOpensRequestedRound() async throws {
        let requested = makeVotingSession(idByte: 0x01, status: .finalized, createdAtHeight: 1, title: "Requested")
        let newer = makeVotingSession(idByte: 0x02, status: .finalized, createdAtHeight: 2, title: "Newer")
        let initialState = Voting.State(
            walletId: "entry-intent-requested",
            entryIntent: .results(roundId: roundId(for: requested))
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        await store.send(.allRoundsLoaded([requested, newer]))

        XCTAssertEqual(store.state.screenStack, [.results])
        XCTAssertEqual(store.state.entryIntent, .normal)
        XCTAssertEqual(store.state.roundId, roundId(for: requested))
        XCTAssertEqual(store.state.votingRound.title, "Requested")
    }

    func testAllRoundsLoadedWithResultsIntentFallsBackToPollsListWhenNoClosedRoundsExist() async throws {
        let active = makeVotingSession(idByte: 0x01, status: .active, createdAtHeight: 1)
        let initialState = Voting.State(walletId: "entry-intent-fallback", entryIntent: .results(roundId: nil))

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        await store.send(.allRoundsLoaded([active]))

        XCTAssertEqual(store.state.screenStack, [.pollsList])
        XCTAssertEqual(store.state.entryIntent, .normal)
        XCTAssertNil(store.state.activeSession)
    }

    func testNonKeystoneDelegationApprovalStartsDelegationProof() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 1,
            isKeystoneUser: false,
            roundId: "aabb"
        )
        initialState.activeSession = VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 1,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: MockVotingService.votingRound.proposals,
            status: .active
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }

        // Mock dependencies accessed by startDelegationProof's .run effect
        store.dependencies.walletStorage = .noOp
        store.dependencies.mnemonic = .noOp
        store.dependencies.databaseFiles = .noOp
        store.dependencies.votingCrypto.buildAndProveDelegation = { _, _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.progress(1.0))
                continuation.yield(.completed(Data(repeating: 0xFF, count: 32)))
                continuation.finish()
            }
        }
        store.dependencies.votingCrypto.getDelegationSubmission = { _, _, _, _, _ in
            DelegationRegistration(
                rk: Data(repeating: 0x01, count: 32),
                spendAuthSig: Data(repeating: 0x02, count: 64),
                signedNoteNullifier: Data(repeating: 0x03, count: 32),
                cmxNew: Data(repeating: 0x04, count: 32),
                vanCmx: Data(repeating: 0x06, count: 32),
                govNullifiers: [],
                proof: Data(repeating: 0x07, count: 32),
                voteRoundId: Data(repeating: 0xAA, count: 32),
                sighash: Data(repeating: 0x08, count: 32)
            )
        }
        store.dependencies.votingCrypto.storeVanPosition = { _, _, _ in }
        store.dependencies.votingAPI.submitDelegation = { _ in
            TxResult(txHash: "mock-hash", code: 0)
        }
        store.dependencies.votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(
                height: 100,
                code: 0,
                events: [
                    TxEvent(type: "delegate_vote", attributes: [
                        TxEventAttribute(key: "vote_round_id", value: "aabb"),
                        TxEventAttribute(key: "leaf_index", value: "5"),
                        TxEventAttribute(key: "nullifier_count", value: "3"),
                    ])
                ]
            )
        }

        await store.send(.delegationApproved) { state in
            state.screenStack = [.proposalList]
            state.delegationProofStatus = .generating(progress: 0)
        }

        await store.receive(.delegationProofProgress(1.0)) { state in
            state.delegationProofStatus = .generating(progress: 1.0)
        }
        await store.receive(.delegationProofCompleted) { state in
            state.delegationProofStatus = .complete
        }
    }

    func testKeystoneSignatureResumesDelegationProofPipeline() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 1,
            isKeystoneUser: true,
            roundId: "aabb"
        )
        initialState.activeSession = VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 1,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: MockVotingService.votingRound.proposals,
            status: .active
        )
        let mockGovPczt = GovernancePcztResult(
            pcztBytes: Data(repeating: 0xAB, count: 128),
            rk: Data(repeating: 0x11, count: 32),
            alpha: Data(repeating: 0x1A, count: 32),
            nfSigned: Data(repeating: 0x18, count: 32),
            cmxNew: Data(repeating: 0x19, count: 32),
            govNullifiers: [Data](repeating: Data(repeating: 0x15, count: 32), count: 4),
            van: Data(repeating: 0x16, count: 32),
            vanCommRand: Data(repeating: 0x03, count: 32),
            dummyNullifiers: [],
            rhoSigned: Data(repeating: 0x04, count: 32),
            paddedCmx: [],
            rseedSigned: Data(repeating: 0x1B, count: 32),
            rseedOutput: Data(repeating: 0x1C, count: 32),
            actionBytes: Data(repeating: 0x10, count: 64),
            actionIndex: 0
        )
        initialState.pendingGovernancePczt = mockGovPczt
        initialState.pendingUnsignedDelegationPczt = Data(repeating: 0xAB, count: 128)

        let store = TestStore(initialState: initialState) {
            Voting()
        }

        store.dependencies.walletStorage = .noOp
        store.dependencies.mnemonic = .noOp
        store.dependencies.databaseFiles = .noOp
        store.dependencies.votingCrypto.extractPcztSighash = { _ in
            Data(repeating: 0x77, count: 32)
        }
        store.dependencies.votingCrypto.buildAndProveDelegation = { _, _, _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.progress(1.0))
                continuation.yield(.completed(Data(repeating: 0xFF, count: 32)))
                continuation.finish()
            }
        }
        store.dependencies.votingCrypto.getDelegationSubmissionWithKeystoneSig = { _, _, sig, sighash in
            DelegationRegistration(
                rk: Data(repeating: 0x11, count: 32),
                spendAuthSig: sig,
                signedNoteNullifier: Data(repeating: 0x03, count: 32),
                cmxNew: Data(repeating: 0x04, count: 32),
                vanCmx: Data(repeating: 0x06, count: 32),
                govNullifiers: [],
                proof: Data(repeating: 0x07, count: 32),
                voteRoundId: Data(repeating: 0xAA, count: 32),
                sighash: sighash
            )
        }
        store.dependencies.votingCrypto.storeVanPosition = { _, _, _ in }
        store.dependencies.votingAPI.submitDelegation = { _ in
            TxResult(txHash: "mock-hash", code: 0)
        }
        store.dependencies.votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(
                height: 100,
                code: 0,
                events: [
                    TxEvent(type: "delegate_vote", attributes: [
                        TxEventAttribute(key: "vote_round_id", value: "aabb"),
                        TxEventAttribute(key: "leaf_index", value: "5"),
                        TxEventAttribute(key: "nullifier_count", value: "3"),
                    ])
                ]
            )
        }

        await store.send(.spendAuthSignatureExtracted(
            Data(repeating: 0x44, count: 64),
            Data(repeating: 0xAB, count: 128)
        )) { state in
            state.pendingGovernancePczt = nil
            state.pendingUnsignedDelegationPczt = nil
            state.keystoneSigningStatus = .idle
            state.screenStack = [.proposalList]
            state.delegationProofStatus = .generating(progress: 0)
        }

        await store.receive(.delegationProofProgress(1.0)) { state in
            state.delegationProofStatus = .generating(progress: 1.0)
        }
        await store.receive(.delegationProofCompleted) { state in
            state.delegationProofStatus = .complete
        }
    }

    // Note: Client-side signature verification was removed — Keystone signatures
    // are correct by construction (signed over the PCZT's ZIP-244 sighash).
    // Verification will be re-added once the GovernancePczt flow is fully wired (Task #6).

    // MARK: - Crash Recovery Tests

    /// Dead State A: App killed after some bundles delegated on-chain.
    /// Recovery state has TX hashes for bundles 0 and 1 (of 3). Both are confirmed.
    /// verifyWitnesses should recover VAN positions and resume (not clearRound).
    func testPartialDelegationRecoverySkipsClearRound() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            roundId: "aabb"
        )
        initialState.activeSession = VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 100,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: MockVotingService.votingRound.proposals,
            status: .active
        )
        initialState.walletNotes = [
            NoteInfo(commitment: Data(repeating: 0x01, count: 32), nullifier: Data(repeating: 0x02, count: 32),
                     value: 50_000_000, position: 0, diversifier: Data(repeating: 0x03, count: 11),
                     rho: Data(repeating: 0x04, count: 32), rseed: Data(repeating: 0x05, count: 32), scope: 0, ufvkStr: "ufvk1")
        ]

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        var clearRoundCalled = false
        store.dependencies.databaseFiles = .noOp
        store.dependencies.sdkSynchronizer = .noOp
        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.votingCrypto.getRoundState = { _ in
            RoundStateInfo(roundId: "aabb", phase: .delegationConstructed, snapshotHeight: 100,
                           hotkeyAddress: nil, delegatedWeight: nil, proofGenerated: false)
        }
        store.dependencies.votingCrypto.getDelegationTxHash = { _, bundleIndex in
            switch bundleIndex {
            case 0: return "tx-hash-0"
            case 1: return "tx-hash-1"
            default: return nil
            }
        }
        store.dependencies.votingCrypto.storeVanPosition = { _, _, _ in }
        store.dependencies.votingCrypto.getBundleCount = { _ in 3 }
        store.dependencies.votingCrypto.clearRound = { _ in clearRoundCalled = true }
        store.dependencies.votingAPI.fetchTxConfirmation = { txHash in
            TxConfirmation(
                height: 200, code: 0,
                events: [TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: txHash == "tx-hash-0" ? "5" : "6")
                ])]
            )
        }

        await store.send(.verifyWitnesses)

        // Recovery should skip clearRound since some TXs are confirmed
        // Instead it should resume with witnessVerificationCompleted
        await store.receive(.witnessPreparationStarted)
        await store.receive(.witnessVerificationCompleted([], [], .init(treeStateFetchMs: 0, witnessGenerationMs: 0, verificationMs: 0), 3))

        XCTAssertFalse(clearRoundCalled, "clearRound should NOT be called when recovery state has confirmed TXs")
    }

    /// Dead State A (full): All delegation TXs confirmed but proofGenerated is false.
    /// verifyWitnesses should recover all VAN positions and resume to proposal list.
    func testFullDelegationRecoveryResumesToProposalList() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            roundId: "aabb"
        )
        initialState.activeSession = VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 100,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: MockVotingService.votingRound.proposals,
            status: .active
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        var vanPositionsStored: [UInt32: UInt32] = [:]
        store.dependencies.databaseFiles = .noOp
        store.dependencies.sdkSynchronizer = .noOp
        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.votingCrypto.getRoundState = { _ in
            RoundStateInfo(roundId: "aabb", phase: .delegationConstructed, snapshotHeight: 100,
                           hotkeyAddress: nil, delegatedWeight: nil, proofGenerated: false)
        }
        store.dependencies.votingCrypto.getDelegationTxHash = { _, bundleIndex in
            bundleIndex == 0 ? "tx-0" : nil
        }
        store.dependencies.votingCrypto.getBundleCount = { _ in 1 }
        store.dependencies.votingCrypto.storeVanPosition = { _, bundleIdx, pos in
            vanPositionsStored[bundleIdx] = pos
        }
        store.dependencies.votingCrypto.clearRecoveryState = { _ in }
        store.dependencies.votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(height: 200, code: 0, events: [
                TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: "42")
                ])
            ])
        }

        await store.send(.verifyWitnesses)
        await store.receive(.roundResumeChecked(alreadyAuthorized: true))

        XCTAssertEqual(vanPositionsStored[0], 42, "VAN position should be recovered from chain event")
    }

    /// Dead State C: Keystone signatures persisted, app restarted.
    /// witnessVerificationCompleted should restore signatures and resume batch proving.
    func testKeystoneSignatureRecoveryResumesBatchProve() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 100_000_000,
            isKeystoneUser: true,
            roundId: "aabb"
        )
        initialState.bundleCount = 1

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        let savedSig = KeystoneBundleSignatureInfo(
            bundleIndex: 0,
            sig: Data(repeating: 0x44, count: 64),
            sighash: Data(repeating: 0x77, count: 32),
            rk: Data(repeating: 0x11, count: 32)
        )
        store.dependencies.votingCrypto.loadKeystoneBundleSignatures = { _ in [savedSig] }

        await store.send(.witnessVerificationCompleted([], [], .init(treeStateFetchMs: 0, witnessGenerationMs: 0, verificationMs: 0), 1)) { state in
            state.noteWitnessResults = []
            state.cachedWitnesses = []
            state.witnessStatus = .completed
            state.bundleCount = 1
        }

        // Should restore the signature and go to batch proving
        await store.receive(.keystoneSignaturesRestored([savedSig])) { state in
            state.keystoneBundleSignatures = [
                Voting.State.KeystoneBundleSignature(
                    sig: Data(repeating: 0x44, count: 64),
                    sighash: Data(repeating: 0x77, count: 32),
                    rk: Data(repeating: 0x11, count: 32)
                )
            ]
            state.currentKeystoneBundleIndex = 1
            state.keystoneSigningStatus = .idle
            state.screenStack = [.proposalList]
            state.delegationProofStatus = .generating(progress: 0)
        }
    }

    /// Dead State C: No saved Keystone signatures.
    /// witnessVerificationCompleted should show the delegation signing screen.
    func testKeystoneNoRecoveryShowsSigningScreen() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 100_000_000,
            isKeystoneUser: true,
            roundId: "aabb"
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        store.dependencies.votingCrypto.loadKeystoneBundleSignatures = { _ in [] }

        await store.send(.witnessVerificationCompleted([], [], .init(treeStateFetchMs: 0, witnessGenerationMs: 0, verificationMs: 0), 1)) { state in
            state.noteWitnessResults = []
            state.cachedWitnesses = []
            state.witnessStatus = .completed
            state.bundleCount = 1
        }

        await store.receive(.keystoneShowSigningScreen) { state in
            state.screenStack = [.delegationSigning]
        }
    }

    /// Skipped bundles: app relaunch via roundResumeChecked (Path A).
    /// bundleCountRestored should recalculate votingWeight for the reduced bundle count.
    func testBundleCountRestoredAdjustsWeightForSkippedBundles() async throws {
        // 6 notes → 2 bundles: bundle 0 = 5×27.8M = 139M, bundle 1 = 1×12.5M = 12.5M
        // eligibleWeight = floor(139M/12.5M)*12.5M + floor(12.5M/12.5M)*12.5M = 150M
        let notes: [NoteInfo] = (0..<5).map { i in
            NoteInfo(
                commitment: Data(repeating: UInt8(i + 1), count: 32),
                nullifier: Data(repeating: UInt8(i + 10), count: 32),
                value: 27_800_000, position: UInt64(i),
                diversifier: Data(repeating: 0x03, count: 11),
                rho: Data(repeating: 0x04, count: 32),
                rseed: Data(repeating: 0x05, count: 32), scope: 0, ufvkStr: "ufvk1"
            )
        } + [
            NoteInfo(
                commitment: Data(repeating: 0x06, count: 32),
                nullifier: Data(repeating: 0x16, count: 32),
                value: 12_500_000, position: 5,
                diversifier: Data(repeating: 0x03, count: 11),
                rho: Data(repeating: 0x04, count: 32),
                rseed: Data(repeating: 0x05, count: 32), scope: 0, ufvkStr: "ufvk1"
            )
        ]

        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 150_000_000,
            isKeystoneUser: true,
            roundId: "aabb"
        )
        initialState.walletNotes = notes

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        await store.send(.bundleCountRestored(1)) { state in
            state.bundleCount = 1
            state.votingWeight = 139_000_000
        }
    }

    /// Skipped bundles: app relaunch via witnessVerificationCompleted (Path B).
    /// Reduced bundleCount from DB should recalculate votingWeight.
    func testWitnessVerificationCompletedAdjustsWeightForSkippedBundles() async throws {
        let notes: [NoteInfo] = (0..<5).map { i in
            NoteInfo(
                commitment: Data(repeating: UInt8(i + 1), count: 32),
                nullifier: Data(repeating: UInt8(i + 10), count: 32),
                value: 27_800_000, position: UInt64(i),
                diversifier: Data(repeating: 0x03, count: 11),
                rho: Data(repeating: 0x04, count: 32),
                rseed: Data(repeating: 0x05, count: 32), scope: 0, ufvkStr: "ufvk1"
            )
        } + [
            NoteInfo(
                commitment: Data(repeating: 0x06, count: 32),
                nullifier: Data(repeating: 0x16, count: 32),
                value: 12_500_000, position: 5,
                diversifier: Data(repeating: 0x03, count: 11),
                rho: Data(repeating: 0x04, count: 32),
                rseed: Data(repeating: 0x05, count: 32), scope: 0, ufvkStr: "ufvk1"
            )
        ]

        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 150_000_000,
            isKeystoneUser: true,
            roundId: "aabb"
        )
        initialState.walletNotes = notes

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off
        store.dependencies.votingCrypto.loadKeystoneBundleSignatures = { _ in [] }

        let timing = Voting.State.WitnessTiming(treeStateFetchMs: 0, witnessGenerationMs: 0, verificationMs: 0)
        await store.send(.witnessVerificationCompleted([], [], timing, 1)) { state in
            state.noteWitnessResults = []
            state.cachedWitnesses = []
            state.witnessStatus = .completed
            state.bundleCount = 1
            state.votingWeight = 139_000_000
        }
    }

    /// Dead State B: Delegation TX hash stored but VAN position not stored before crash.
    /// On resume, verifyWitnesses should recover the VAN position from the chain event.
    func testDelegationTxHashRecoveryStoresVanPosition() async throws {
        var initialState = Voting.State(
            votingRound: MockVotingService.votingRound,
            votingWeight: 100_000_000,
            isKeystoneUser: false,
            roundId: "aabb"
        )
        initialState.activeSession = VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 100,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: MockVotingService.votingRound.proposals,
            status: .active
        )

        let store = TestStore(initialState: initialState) {
            Voting()
        }
        store.exhaustivity = .off

        var storedPositions: [(UInt32, UInt32)] = []
        store.dependencies.databaseFiles = .noOp
        store.dependencies.sdkSynchronizer = .noOp
        store.dependencies.zcashSDKEnvironment = .testValue
        store.dependencies.votingCrypto.getRoundState = { _ in
            RoundStateInfo(roundId: "aabb", phase: .delegationProved, snapshotHeight: 100,
                           hotkeyAddress: nil, delegatedWeight: nil, proofGenerated: false)
        }
        store.dependencies.votingCrypto.getDelegationTxHash = { _, bundleIndex in
            bundleIndex == 0 ? "delegation-tx-42" : nil
        }
        store.dependencies.votingCrypto.getBundleCount = { _ in 1 }
        store.dependencies.votingCrypto.storeVanPosition = { _, bundleIdx, pos in
            storedPositions.append((bundleIdx, pos))
        }
        store.dependencies.votingCrypto.clearRecoveryState = { _ in }
        store.dependencies.votingAPI.fetchTxConfirmation = { _ in
            TxConfirmation(height: 300, code: 0, events: [
                TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: "99")
                ])
            ])
        }

        await store.send(.verifyWitnesses)
        await store.receive(.roundResumeChecked(alreadyAuthorized: true))

        XCTAssertEqual(storedPositions.count, 1)
        XCTAssertEqual(storedPositions.first?.0, 0, "Should store position for bundle 0")
        XCTAssertEqual(storedPositions.first?.1, 99, "Should store VAN position 99 from chain event")
    }

    private func makeVotingSession(
        idByte: UInt8,
        status: SessionStatus,
        createdAtHeight: UInt64,
        title: String = "Round"
    ) -> VotingSession {
        VotingSession(
            voteRoundId: Data(repeating: idByte, count: 32),
            snapshotHeight: 100,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(createdAtHeight)),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            proposals: [
                Proposal(
                    id: 1,
                    title: "test",
                    description: "test",
                    options: [
                        VoteOption(index: 0, label: "Support"),
                        VoteOption(index: 1, label: "Oppose")
                    ]
                )
            ],
            status: status,
            createdAtHeight: createdAtHeight,
            title: title
        )
    }

    private func roundId(for session: VotingSession) -> String {
        session.voteRoundId.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - TX Event Parsing Tests
//
// These validate that the TxEvent / TxConfirmation model helpers correctly
// extract leaf indices from realistic Cosmos SDK TX response payloads matching
// what the vote-sdk chain emits for delegate_vote and cast_vote.

final class TxEventParsingTests: XCTestCase {

    // MARK: - delegate_vote (ZKP #1)
    // Chain emits: leaf_index = "<vanCmxIdx>" (single uint)

    func testDelegateVoteEventLeafIndex() {
        let confirmation = TxConfirmation(
            height: 1042,
            code: 0,
            log: "",
            events: [
                TxEvent(type: "message", attributes: [
                    TxEventAttribute(key: "action", value: "/svote.vote.MsgDelegateVote"),
                    TxEventAttribute(key: "sender", value: "cosmos1abc"),
                ]),
                TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "vote_round_id", value: "aabbccdd"),
                    TxEventAttribute(key: "leaf_index", value: "7"),
                    TxEventAttribute(key: "nullifier_count", value: "4"),
                ]),
            ]
        )

        let event = confirmation.event(ofType: "delegate_vote")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.attribute(forKey: "leaf_index"), "7")
        XCTAssertEqual(UInt32(event!.attribute(forKey: "leaf_index")!), 7)
    }

    func testDelegateVoteMultipleBundlesGetDistinctIndices() {
        let bundle0Confirmation = TxConfirmation(
            height: 1042, code: 0, events: [
                TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: "0"),
                ]),
            ]
        )
        let bundle1Confirmation = TxConfirmation(
            height: 1043, code: 0, events: [
                TxEvent(type: "delegate_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: "1"),
                ]),
            ]
        )

        let idx0 = UInt32(bundle0Confirmation.event(ofType: "delegate_vote")!.attribute(forKey: "leaf_index")!)
        let idx1 = UInt32(bundle1Confirmation.event(ofType: "delegate_vote")!.attribute(forKey: "leaf_index")!)
        XCTAssertEqual(idx0, 0)
        XCTAssertEqual(idx1, 1)
        XCTAssertNotEqual(idx0, idx1)
    }

    // MARK: - cast_vote (ZKP #2)
    // Chain emits: leaf_index = "<vanIdx>,<vcIdx>" (comma-separated pair)

    func testCastVoteEventLeafIndices() {
        let confirmation = TxConfirmation(
            height: 2001,
            code: 0,
            log: "",
            events: [
                TxEvent(type: "message", attributes: [
                    TxEventAttribute(key: "action", value: "/svote.vote.MsgCastVote"),
                ]),
                TxEvent(type: "cast_vote", attributes: [
                    TxEventAttribute(key: "vote_round_id", value: "aabbccdd"),
                    TxEventAttribute(key: "leaf_index", value: "10,11"),
                ]),
            ]
        )

        let leafPair = confirmation.event(ofType: "cast_vote")?.attribute(forKey: "leaf_index")
        XCTAssertEqual(leafPair, "10,11")

        let parts = leafPair!.split(separator: ",")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(UInt64(parts[0]), 10)
        XCTAssertEqual(UInt64(parts[1]), 11)
    }

    func testCastVoteHighLeafIndicesFromConcurrentBlock() {
        let confirmation = TxConfirmation(
            height: 5000, code: 0, events: [
                TxEvent(type: "cast_vote", attributes: [
                    TxEventAttribute(key: "leaf_index", value: "1048576,1048577"),
                ]),
            ]
        )

        let leafPair = confirmation.event(ofType: "cast_vote")!.attribute(forKey: "leaf_index")!
        let parts = leafPair.split(separator: ",")
        XCTAssertEqual(UInt64(parts[0]), 1_048_576)
        XCTAssertEqual(UInt64(parts[1]), 1_048_577)
    }

    // MARK: - Edge cases

    func testMissingEventReturnsNil() {
        let confirmation = TxConfirmation(
            height: 100, code: 0, events: [
                TxEvent(type: "message", attributes: [
                    TxEventAttribute(key: "action", value: "/svote.vote.MsgDelegateVote"),
                ]),
            ]
        )
        XCTAssertNil(confirmation.event(ofType: "delegate_vote"))
        XCTAssertNil(confirmation.event(ofType: "cast_vote"))
    }

    func testFailedTxCodeNonZero() {
        let confirmation = TxConfirmation(
            height: 100, code: 5, log: "nullifier already spent", events: []
        )
        XCTAssertNotEqual(confirmation.code, 0)
        XCTAssertNil(confirmation.event(ofType: "delegate_vote"))
    }

    func testEventAttributeForKeyMiss() {
        let event = TxEvent(type: "delegate_vote", attributes: [
            TxEventAttribute(key: "vote_round_id", value: "aabb"),
        ])
        XCTAssertNil(event.attribute(forKey: "leaf_index"))
    }

    func testEmptyEventsArray() {
        let confirmation = TxConfirmation(height: 100, code: 0, events: [])
        XCTAssertNil(confirmation.event(ofType: "delegate_vote"))
        XCTAssertNil(confirmation.event(ofType: "cast_vote"))
    }
}
