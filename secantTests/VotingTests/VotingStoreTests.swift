import XCTest
import ComposableArchitecture
import DatabaseFiles
import MnemonicClient
import Voting
import VotingModels
import WalletStorage
@testable import secant_testnet

@MainActor
final class VotingStoreTests: XCTestCase {
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
