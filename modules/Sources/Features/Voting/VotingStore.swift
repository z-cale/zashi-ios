// swiftlint:disable file_length
import Combine
import Foundation
import ComposableArchitecture
import DatabaseFiles
import Generated
import KeystoneHandler
import MnemonicClient
import Models
import Pasteboard
import Scan
import SDKSynchronizer
import BackgroundTaskClient
import UIComponents
import Utils
import VotingAPIClient
import VotingCryptoClient
import VotingModels
import WalletStorage
import ZcashSDKEnvironment
import ZcashLightClientKit
import os

private let logger = Logger(subsystem: "co.zodl.voting", category: "VotingStore")

private enum VotingFlowError: LocalizedError {
    case missingActiveSession
    case missingSigningAccount
    case missingHotkeyAddress
    case missingPendingUnsignedPczt
    case invalidDelegationSignature
    case missingVoteCommitmentBundle
    case delegationTxFailed(code: UInt32)
    case voteCommitmentTxFailed(code: UInt32)

    var errorDescription: String? {
        switch self {
        case .missingActiveSession:
            return "missing active voting session"
        case .missingSigningAccount:
            return "missing signing account for delegation PCZT"
        case .missingHotkeyAddress:
            return "missing hotkey address for delegation PCZT"
        case .missingPendingUnsignedPczt:
            return "missing pending unsigned delegation PCZT"
        case .invalidDelegationSignature:
            return "Keystone delegation signature tuple (rk, sighash, sig) is inconsistent with the payload being submitted."
        case .missingVoteCommitmentBundle:
            return "vote commitment build completed without a commitment bundle"
        case .delegationTxFailed(let code):
            return "delegation TX failed on-chain (code \(code)) or missing delegate_vote event"
        case .voteCommitmentTxFailed(code: let code):
            return "vote commitment TX failed on-chain (code \(code))"
        }
    }
}

private enum VotingErrorMapper {
    static func userFriendlyMessage(from rawError: String) -> String {
        if rawError.contains("nullifier already spent") {
            return "This wallet has already been registered for this voting round. "
                + "If you have this wallet on multiple devices, please use the device "
                + "where you originally started the voting process."
        }
        if rawError.contains("vote round is not active") {
            return "This voting round is no longer accepting votes. It may have ended or is not yet open."
        }
        if rawError.contains("vote round not found") {
            return "This voting round could not be found on the network."
        }
        if rawError.contains("PIR server connect failed") || rawError.contains("PIR parallel fetch failed") {
            return "Unable to reach the nullifier service. Please check your internet connection and try again."
        }
        if rawError.contains("Commitment tree did not grow") {
            return "Your transaction hasn't been confirmed yet. The network may be congested — please wait a moment and try again."
        }
        if rawError.contains("invalid commitment tree anchor height") {
            return "The voting state is out of sync. Please retry to use the latest data."
        }
        if rawError.contains("invalid zero-knowledge proof") {
            return "Your proof was rejected by the network. Please try again."
        }
        if rawError.contains("delegation bundle build failed") || rawError.contains("create_proof failed") {
            return "Proof generation failed. Please try again."
        }
        if rawError.contains("NoTreeState") || rawError.contains("no tree state") {
            return "The voting commitment tree is not available yet. The voting round may not have started or the chain has not processed any commitments."
        }
        if rawError.contains("HTTP 5") {
            return "The voting server is temporarily unavailable. Please try again shortly."
        }
        if rawError.contains("GRPCStatus") || rawError.contains("RPC timed out") || rawError.contains("Transport became inactive") {
            return "Unable to reach the Zcash lightwalletd server. Please check your internet connection or try switching to a different server in Settings."
        }
        return rawError
    }
}

@Reducer
public struct Voting { // swiftlint:disable:this type_body_length
    @Dependency(\.backgroundTask)
    var backgroundTask
    @Dependency(\.databaseFiles)
    var databaseFiles
    @Dependency(\.keystoneHandler)
    var keystoneHandler
    @Dependency(\.mnemonic)
    var mnemonic
    @Dependency(\.pasteboard)
    var pasteboard
    @Dependency(\.sdkSynchronizer)
    var sdkSynchronizer
    @Dependency(\.votingAPI)
    var votingAPI
    @Dependency(\.votingCrypto)
    var votingCrypto
    @Dependency(\.localAuthentication)
    var localAuthentication
    @Dependency(\.walletStorage)
    var walletStorage
    @Dependency(\.zcashSDKEnvironment)
    var zcashSDKEnvironment
    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            case howToVote
            case loading
            case noRounds
            case pollsList
            case delegationSigning
            case proposalList
            case proposalDetail(id: UInt32)
            case complete
            case ineligible
            case tallying
            case results
            case reviewVotes
            case confirmSubmission
            case error(String)
            case configError(String)
            case walletSyncing
        }

        public struct RoundListItem: Equatable, Identifiable {
            public var id: String { session.voteRoundId.hexString }
            public let roundNumber: Int
            public let session: VotingSession
            public var title: String {
                session.title.isEmpty ? "Round \(roundNumber)" : session.title
            }
        }

        public struct NoteWitnessResult: Equatable, Identifiable {
            public var id: UInt64 { position }
            public let position: UInt64
            public let value: UInt64
            public let verified: Bool
        }

        public enum WitnessStatus: Equatable {
            case notStarted
            case inProgress
            case completed
            case failed(String)
        }

        public struct WitnessTiming: Equatable {
            public let treeStateFetchMs: UInt64
            public let witnessGenerationMs: UInt64
            public let verificationMs: UInt64
            public var totalMs: UInt64 { treeStateFetchMs + witnessGenerationMs + verificationMs }
        }

        public enum KeystoneSigningStatus: Equatable {
            case idle
            case preparingRequest
            case awaitingSignature
            case parsingSignature
            case failed(String)
        }

        public enum IneligibilityReason: Equatable {
            case noNotes
            case balanceTooLow
        }

        public enum VoteSubmissionStep: Equatable {
            case authorizingVote    // delegation proof (ZKP #1)
            case preparingProof     // syncVoteTree + generateVanWitness + buildVoteCommitment + signCastVote + submitVoteCommitment
            case confirming         // fetchTxConfirmation poll
            case sendingShares      // buildSharePayloads + delegateShares

            public var label: String {
                switch self {
                case .authorizingVote: return "Authorizing vote..."
                case .preparingProof: return "Building vote proof..."
                case .confirming: return "Waiting for confirmation..."
                case .sendingShares: return "Sending to vote servers..."
                }
            }

            public var stepNumber: Int {
                switch self {
                case .authorizingVote: return 1
                case .preparingProof: return 2
                case .confirming: return 3
                case .sendingShares: return 4
                }
            }

            public static let totalSteps = 4
        }

        public var screenStack: [Screen] = [.howToVote]
        public var votingRound: VotingRound
        public var votes: [UInt32: VoteChoice] = [:]
        public var votingWeight: UInt64
        public var isKeystoneUser: Bool
        public var walletId: String
        public var roundId: String
        public var activeSession: VotingSession?

        /// All rounds fetched from the server, sorted by snapshot height and numbered.
        public var allRounds: [RoundListItem] = []
        /// Computed: rounds that are active or tallying (newest first).
        public var activeRounds: [RoundListItem] {
            allRounds.filter { $0.session.status == .active || $0.session.status == .tallying }.reversed()
        }

        /// Computed: rounds that are finalized (newest first).
        public var completedRounds: [RoundListItem] {
            allRounds.filter { $0.session.status == .finalized }.reversed()
        }

        /// Resolved service config from CDN or local override.
        public var serviceConfig: VotingServiceConfig?

        /// Set after one attempted lazy config refresh during the current session.
        /// Prevents a refresh → allRoundsLoaded → refresh loop when the fresh config still doesn't match.
        public var hasAttemptedConfigRefresh: Bool = false

        /// Tally results for finalized rounds (proposalId → TallyResult).
        public var tallyResults: [UInt32: TallyResult] = [:]
        public var isLoadingTallyResults: Bool = false

        /// Reason the user can't participate (set when navigating to .ineligible).
        public var ineligibilityReason: IneligibilityReason?

        /// Wallet sync progress info for the walletSyncing screen.
        public var walletScannedHeight: UInt64 = 0

        /// Per-proposal share confirmation tracking (proposalId → confirmed count 0-5).

        // Share delegation tracking (DB-backed, per-round)
        public var shareTrackingStatus: ShareTrackingStatus = .idle
        public var shareDelegations: [VotingShareDelegation] = []
        public var showShareInfoSheet: Bool = false
        public var shareInfoProposalId: UInt32?

        public enum ShareTrackingStatus: Equatable {
            case idle
            case loading
            case tracking
            case fullyConfirmed
        }

        /// Cached wallet notes from the snapshot query, used by delegation proof.
        public var walletNotes: [NoteInfo] = []

        /// Number of note bundles (groups of up to 5 notes). Set by setupBundles.
        public var bundleCount: UInt32 = 0

        /// Hotkey address derived from keychain mnemonic, shown on delegation signing screen.
        public var hotkeyAddress: String?

        @Shared(.inMemory(.selectedWalletAccount))
        public var selectedWalletAccount: WalletAccount?
        @Shared(.inMemory(.toast))
        public var toast: Toast.Edge?
        @Shared(.appStorage(.hasSeenHowToVote))
        public var hasSeenHowToVote: Bool = false

        /// Persisted record of when the user confirmed their vote in the current
        /// round, loaded from UserDefaults in `roundTapped`. Used by Results to
        /// render "Voted MMM d · Voting Power X.XXX ZEC" days after submission.
        public var voteRecord: VoteRecord?

        /// Per-round persisted vote records keyed by round ID, populated by a
        /// one-time scan of UserDefaults during `allRoundsLoaded`. The polls
        /// list uses this to render the Voted pill on active-round cards and
        /// the "X of Y voted" indicator on closed cards without re-querying
        /// UserDefaults from the view.
        public var voteRecords: [String: VoteRecord] = [:]

        public var selectedProposalId: UInt32?

        // MARK: - Batch voting

        /// Draft votes (batch mode): proposal ID → chosen option. Persisted to
        /// UserDefaults to survive app termination. Drafts are not submitted
        /// until the user explicitly triggers batch submission.
        public var draftVotes: [UInt32: VoteChoice] = [:]

        public enum BatchSubmissionStatus: Equatable {
            case idle
            case authorizing
            case submitting(currentIndex: Int, totalCount: Int, currentProposalId: UInt32)
            case completed(successCount: Int, failCount: Int)
            case failed(lastError: String, submittedCount: Int, totalCount: Int)
        }

        public var batchSubmissionStatus: BatchSubmissionStatus = .idle
        /// Per-proposal error messages from the last batch submission run.
        public var batchVoteErrors: [UInt32: String] = [:]

        /// Signals that batch submission should resume after delegation completes (Keystone path).
        public var pendingBatchSubmission: Bool = false

        // Witness verification results
        public var noteWitnessResults: [NoteWitnessResult] = []
        public var witnessStatus: WitnessStatus = .notStarted
        /// Cached witness data from verification, used as inclusion proofs for delegation proof.
        public var cachedWitnesses: [WitnessData] = []
        /// Timing breakdown from the last witness generation run.
        public var witnessTiming: WitnessTiming?

        // ZKP #1 (delegation) — runs in background
        public var delegationProofStatus: ProofStatus = .notStarted
        /// True while the delegation proof `.run` effect is in-flight. Guards against
        /// re-entrant `.startDelegationProof` dispatches from round polling re-triggers.
        public var isDelegationProofInFlight: Bool = false
        public var keystoneSigningStatus: KeystoneSigningStatus = .idle

        /// Which bundle the Keystone signing loop is currently processing (0-based).
        public var currentKeystoneBundleIndex: UInt32 = 0

        /// Per-bundle Keystone signature data collected during the multi-bundle signing loop.
        public struct KeystoneBundleSignature: Equatable {
            public let sig: Data
            public let sighash: Data
            public let rk: Data // swiftlint:disable:this identifier_name
        }

        /// Collected Keystone signatures for each bundle, accumulated during the signing loop.
        public var keystoneBundleSignatures: [KeystoneBundleSignature] = []

        /// Governance PCZT result for Keystone signing flow (contains metadata + pczt_bytes).
        public var pendingGovernancePczt: GovernancePcztResult?
        /// Unsigned delegation PCZT request shown as QR and used for signature extraction.
        public var pendingUnsignedDelegationPczt: Pczt?
        @Presents public var keystoneScan: Scan.State?
        @Presents public var skipBundlesAlert: AlertState<Action>?

        /// Whether a vote commitment is being built and submitted to chain.
        public var isSubmittingVote: Bool = false
        /// Current step in the vote submission pipeline.
        public var voteSubmissionStep: VoteSubmissionStep?
        /// Which bundle is currently being voted (0-based), nil when not submitting.
        public var currentVoteBundleIndex: UInt32?
        /// Which proposal is currently being submitted, nil when idle.
        public var submittingProposalId: UInt32?

        /// Label for the current vote submission step, with bundle progress when applicable.
        public var voteSubmissionStepLabel: String? {
            guard let step = voteSubmissionStep else { return nil }
            // Show delegation proof percentage during authorization step.
            if step == .authorizingVote, case .generating(let progress) = delegationProofStatus {
                return "Authorizing vote... \(Int(progress * 100))%"
            }
            if bundleCount > 1, let idx = currentVoteBundleIndex {
                let bundleLabel = "(\(idx + 1)/\(bundleCount))"
                switch step {
                case .authorizingVote: return step.label
                case .preparingProof: return "Building vote proof \(bundleLabel)..."
                case .confirming: return "Waiting for confirmation \(bundleLabel)..."
                case .sendingShares: return "Sending to vote servers \(bundleLabel)..."
                }
            }
            return step.label
        }

        public var currentScreen: Screen {
            screenStack.last ?? .pollsList
        }

        public var votingWeightZECString: String {
            let zec = Double(votingWeight) / 100_000_000.0
            return String(format: "%.3f", zec)
        }

        /// Quantized ZEC value for the current Keystone bundle.
        public var currentBundleZECString: String? {
            guard isKeystoneUser, bundleCount > 1 else { return nil }
            let bundles = walletNotes.smartBundles().bundles
            let idx = Int(currentKeystoneBundleIndex)
            guard idx < bundles.count else { return nil }
            let raw = bundles[idx].reduce(UInt64(0)) { $0 + $1.value }
            let weight = quantizeWeight(raw)
            return String(format: "%.3f", Double(weight) / 100_000_000.0)
        }

        /// Quantized ZEC weight already signed across collected Keystone bundle signatures.
        public var signedBundlesZECString: String {
            let bundles = walletNotes.smartBundles().bundles
            let signedWeight = keystoneBundleSignatures.indices.reduce(UInt64(0)) { total, i in
                guard i < bundles.count else { return total }
                let raw = bundles[i].reduce(UInt64(0)) { $0 + $1.value }
                return total + quantizeWeight(raw)
            }
            return String(format: "%.3f", Double(signedWeight) / 100_000_000.0)
        }

        /// Quantized ZEC weight in unsigned bundles that would be given up by skipping.
        public var skippedBundlesZECString: String {
            let bundles = walletNotes.smartBundles().bundles
            let signedCount = keystoneBundleSignatures.count
            let skippedWeight = (signedCount..<bundles.count).reduce(UInt64(0)) { total, i in
                let raw = bundles[i].reduce(UInt64(0)) { $0 + $1.value }
                return total + quantizeWeight(raw)
            }
            return String(format: "%.3f", Double(skippedWeight) / 100_000_000.0)
        }

        /// Raw ZEC weight for the memo — per-bundle for Keystone multi-bundle, total otherwise.
        public var memoWeightZatoshi: UInt64 {
            if isKeystoneUser, bundleCount > 1 {
                let bundles = walletNotes.smartBundles().bundles
                let idx = Int(currentKeystoneBundleIndex)
                if idx < bundles.count {
                    return bundles[idx].reduce(UInt64(0)) { $0 + $1.value }
                }
            }
            return walletNotes.reduce(UInt64(0)) { $0 + $1.value }
        }

        public var isBatchSubmitting: Bool {
            switch batchSubmissionStatus {
            case .authorizing, .submitting: return true
            default: return false
            }
        }

        /// Whether the user can start a submission: bundles resolved,
        /// no other submission in-flight, and at least one draft exists.
        /// Delegation (ZKP #1) runs at submission time, not upfront.
        public var canSubmitBatch: Bool {
            bundleCount > 0 && !isSubmittingVote && !isBatchSubmitting && !draftVotes.isEmpty
        }

        public var votedCount: Int {
            votes.count
        }

        public var totalProposals: Int {
            votingRound.proposals.count
        }

        public var allVoted: Bool {
            votedCount == totalProposals
        }

        public var isDelegationReady: Bool {
            delegationProofStatus == .complete
        }

        /// Whether all share delegations have been confirmed on-chain.
        public var allSharesConfirmed: Bool {
            !shareDelegations.isEmpty && shareDelegations.allSatisfy(\.confirmed)
        }

        /// Per-proposal share delegation progress from the local DB.
        /// Uses a helper struct because tuple values don't conform to Equatable.
        public struct ShareDelegationProgress: Equatable {
            public let confirmed: Int
            public let total: Int
        }

        public var shareDelegationProgressByProposal: [UInt32: ShareDelegationProgress] {
            var result: [UInt32: ShareDelegationProgress] = [:]
            for delegation in shareDelegations {
                let key = delegation.proposalId
                let current = result[key] ?? ShareDelegationProgress(confirmed: 0, total: 0)
                result[key] = ShareDelegationProgress(
                    confirmed: current.confirmed + (delegation.confirmed ? 1 : 0),
                    total: current.total + 1
                )
            }
            return result
        }

        /// Estimated time when all pending shares will have been submitted by helpers.
        public var estimatedCompletionDate: Date? {
            estimatedCompletion(for: shareDelegations)
        }

        /// Estimated completion scoped to the proposal currently shown in the info sheet.
        public var shareInfoEstimatedCompletion: Date? {
            guard let pid = shareInfoProposalId else { return estimatedCompletionDate }
            return estimatedCompletion(for: shareDelegations.filter { $0.proposalId == pid })
        }

        private func estimatedCompletion(for delegations: [VotingShareDelegation]) -> Date? {
            let unconfirmed = delegations.filter { !$0.confirmed }
            guard let maxSubmitAt = unconfirmed.map(\.submitAt).max(), maxSubmitAt > 0 else {
                return nil
            }
            return Date(timeIntervalSince1970: Double(maxSubmitAt))
        }

        public var nextUnvotedProposalId: UInt32? {
            votingRound.proposals.first { votes[$0.id] == nil }?.id
        }

        public var nextUndraftedProposalId: UInt32? {
            votingRound.proposals.first { draftVotes[$0.id] == nil }?.id
        }

        public var allDrafted: Bool {
            !votingRound.proposals.isEmpty &&
            votingRound.proposals.allSatisfy { draftVotes[$0.id] != nil }
        }

        /// Whether the current proposal detail was opened from the review screen.
        public var isEditingFromReview: Bool {
            guard case .proposalDetail = screenStack.last else { return false }
            return screenStack.dropLast().last == .reviewVotes
        }

        public var activeProposalId: UInt32? {
            selectedProposalId ?? nextUnvotedProposalId
        }

        public var selectedProposal: VotingModels.Proposal? {
            if case .proposalDetail(let id) = currentScreen {
                return votingRound.proposals.first { $0.id == id }
            }
            return nil
        }

        // Index of the proposal currently shown in detail
        public var detailProposalIndex: Int? {
            if case .proposalDetail(let id) = currentScreen {
                return votingRound.proposals.firstIndex { $0.id == id }
            }
            return nil
        }

        public init(
            votingRound: VotingRound = VotingRound(
                id: "",
                title: "",
                description: "",
                snapshotHeight: 0,
                snapshotDate: .now,
                votingStart: .now,
                votingEnd: .now,
                proposals: []
            ),
            votingWeight: UInt64 = 0,
            isKeystoneUser: Bool = false,
            walletId: String = "",
            roundId: String = ""
        ) {
            self.votingRound = votingRound
            self.votingWeight = votingWeight
            self.isKeystoneUser = isKeystoneUser
            self.walletId = walletId
            self.roundId = roundId
        }
    }

    let cancelStateStreamId = UUID()
    let cancelStatusPollingId = UUID()
    let cancelPipelineId = UUID()
    let cancelNewRoundPollingId = UUID()
    let cancelShareTrackingId = UUID()

    public enum Action: Equatable {
        // Navigation
        case dismissFlow
        case goBack
        case backToRoundsList
        case howToVoteContinueTapped
        case viewMyVotesTapped(roundId: String)

        // Rounds list
        case allRoundsLoaded([VotingSession])
        case roundTapped(String)
        case startNewRoundPolling

        // Initialization (DB, wallet notes, hotkey)
        case initialize
        case serviceConfigLoaded(VotingServiceConfig)
        case configUnsupported(String)
        case activeSessionLoaded(VotingSession)
        case noActiveRound
        case votingWeightLoaded(UInt64, [NoteInfo])
        case initializeFailed(String)
        case walletNotSynced(scannedHeight: UInt64, snapshotHeight: UInt64)
        case walletSyncProgressUpdated(UInt64)
        case hotkeyLoaded(String)
        case startActiveRoundPipeline

        // DB state stream (single source of truth)
        case votingDbStateChanged(VotingDbState)

        // Witness verification
        case verifyWitnesses
        case witnessPreparationStarted
        case rerunWitnessVerification
        case witnessVerificationCompleted([State.NoteWitnessResult], [WitnessData], State.WitnessTiming, UInt32)
        case witnessVerificationFailed(String)

        // Round resume check (skip delegation screen if already authorized)
        case roundResumeChecked(alreadyAuthorized: Bool)
        case bundleCountRestored(UInt32)

        // Delegation signing
        case copyHotkeyAddress
        case delegationApproved
        case delegationRejected
        case keystoneSigningPrepared(GovernancePcztResult, Pczt)
        case keystoneSigningFailed(String)
        case openKeystoneSignatureScan
        case retryKeystoneSigning
        case spendAuthSignatureExtracted(Data, Data)
        case spendAuthSignatureExtractionFailed(String)
        case keystoneBundleAdvance
        case keystoneBundleSignatureStored(State.KeystoneBundleSignature, bundleIndex: UInt32, bundleCount: UInt32)
        case keystoneAllBundlesSigned
        case keystoneSignaturesRestored([KeystoneBundleSignatureInfo])
        case keystoneShowSigningScreen
        case skipRemainingKeystoneBundles
        case skipBundlesAlert(PresentationAction<Action>)
        case skipRemainingKeystoneBundlesConfirmed
        case keystoneScan(PresentationAction<Scan.Action>)

        // Background ZKP delegation
        case startDelegationProof
        case delegationProofProgress(Double)
        case delegationProofCompleted
        case delegationProofFailed(String)

        // Proposal list
        case proposalTapped(UInt32)

        // Proposal detail
        case castVote(proposalId: UInt32, choice: VoteChoice)
        case voteSubmissionBundleStarted(UInt32)
        case voteSubmissionStepUpdated(State.VoteSubmissionStep)
        case advanceAfterVote
        case backToList
        case nextProposalDetail
        case previousProposalDetail
        case navigateToReview
        case confirmUnanswered
        case dismissUnanswered
        case navigateToConfirmation

        // Round status polling
        case startRoundStatusPolling
        case roundStatusUpdated(roundId: Data, SessionStatus)

        // Tally results
        case fetchTallyResults
        case tallyResultsLoaded([UInt32: TallyResult])

        // Share info sheet
        case showShareInfo(UInt32)
        case hideShareInfo

        // Governance tab lifecycle
        case governanceTabAppeared
        case governanceTabDisappeared

        // Share delegation tracking (DB-backed polling)
        case loadShareDelegations
        case shareDelegationsLoaded([VotingShareDelegation])
        // Updates state from poll loop WITHOUT starting a new poll (avoids fork bomb).
        case shareDelegationsRefreshed([VotingShareDelegation])
        case pollShareStatus

        // Batch voting
        case setDraftVote(proposalId: UInt32, choice: VoteChoice)
        case clearDraftVote(proposalId: UInt32)
        case submitAllDrafts
        case authenticationSucceeded
        case batchSubmissionProgress(currentIndex: Int, totalCount: Int, proposalId: UInt32)
        case batchVoteSubmitted(proposalId: UInt32, choice: VoteChoice)
        case batchVoteFailed(proposalId: UInt32, error: String)
        case batchSubmissionCompleted(successCount: Int, failCount: Int)
        case batchSubmissionFailed(error: String, submittedCount: Int, totalCount: Int)
        case dismissBatchResults

        // Complete
        case doneTapped
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // MARK: - Navigation

            case .dismissFlow:
                state.screenStack = [.loading]
                return .merge(
                    .cancel(id: cancelStateStreamId),
                    .cancel(id: cancelStatusPollingId),
                    .cancel(id: cancelPipelineId),
                    .cancel(id: cancelNewRoundPollingId),
                    .cancel(id: cancelShareTrackingId)
                )

            case .goBack:
                if state.screenStack.count > 1 {
                    state.screenStack.removeLast()
                }
                return .none

            case .howToVoteContinueTapped:
                state.$hasSeenHowToVote.withLock { $0 = true }
                state.screenStack = [.loading]
                return .send(.initialize)

            case .viewMyVotesTapped(let roundId):
                // Reuse roundTapped to load the session and navigate into it.
                // The proposal list will show confirmed votes in read-only mode.
                return .send(.roundTapped(roundId))

            case .backToRoundsList:
                // Cancel per-round effects and re-fetch rounds. allRoundsLoaded
                // sees the cleared activeSession and re-renders the polls list.
                state.screenStack = [.loading]
                // Clean up persisted drafts for the current round
                Self.clearPersistedDrafts(walletId: state.walletId, roundId: state.roundId)
                // Reset per-round state
                state.activeSession = nil
                state.votes = [:]
                state.votingWeight = 0
                state.walletNotes = []
                state.noteWitnessResults = []
                state.cachedWitnesses = []
                state.witnessTiming = nil
                state.witnessStatus = .notStarted
                state.delegationProofStatus = .notStarted
                state.isDelegationProofInFlight = false
                state.hotkeyAddress = nil
                state.isSubmittingVote = false
                state.submittingProposalId = nil
                state.voteSubmissionStep = nil
                state.currentVoteBundleIndex = nil
                state.draftVotes = [:]
                state.batchSubmissionStatus = .idle
                state.batchVoteErrors = [:]
                state.tallyResults = [:]
                state.isLoadingTallyResults = false
                state.ineligibilityReason = nil
                state.showShareInfoSheet = false
                state.shareTrackingStatus = .idle
                state.shareDelegations = []
                state.voteRecord = nil
                // Refresh the rounds list
                return .merge(
                    .cancel(id: cancelStateStreamId),
                    .cancel(id: cancelStatusPollingId),
                    .cancel(id: cancelPipelineId),
                    .cancel(id: cancelNewRoundPollingId),
                    .cancel(id: cancelShareTrackingId),
                    .run { [votingAPI] send in
                        let allRounds = try await votingAPI.fetchAllRounds()
                        await send(.allRoundsLoaded(allRounds))
                    } catch: { error, _ in
                        logger.error("Failed to refresh rounds list: \(error)")
                    }
                )

            // MARK: - Rounds List

            case .allRoundsLoaded(let sessions):
                // Bind the CDN config to its chain round and verify proposals match.
                // Per ZIP 1244, the config is published per-round and must pin exactly
                // one on-chain round via `vote_round_id`; the `proposals_hash` commits
                // to the proposals the user will see.
                //
                // Skip the binding check when the chain has no rounds at all — that's a
                // legitimate "no active voting" state, not a tampered config, and the
                // existing noRounds-screen branch below handles it.
                if let config = state.serviceConfig, !sessions.isEmpty {
                    let configRoundId = config.voteRoundId.lowercased()
                    let hasMatch = sessions.contains { $0.voteRoundId.hexString == configRoundId }

                    // Stale-config recovery: if the cached config doesn't match any on-chain
                    // round (e.g. a new round activated while the wallet was open), attempt
                    // one fresh fetch before bricking. The flag gates the retry so we don't
                    // loop when the fresh config still doesn't bind.
                    if !hasMatch && !state.hasAttemptedConfigRefresh {
                        state.hasAttemptedConfigRefresh = true
                        logger.info("Config round \(configRoundId.prefix(16))... not in chain rounds; refreshing config")
                        return .run { [votingAPI] send in
                            let fresh = try await votingAPI.fetchServiceConfig()
                            await send(.serviceConfigLoaded(fresh))
                        } catch: { error, send in
                            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            await send(.configUnsupported(message))
                        }
                    }

                    guard let matchingSession = sessions.first(where: { $0.voteRoundId.hexString == configRoundId }) else {
                        let chainIds = sessions.map { $0.voteRoundId.hexString.prefix(16) }.joined(separator: ", ")
                        logger.error("Config round \(configRoundId.prefix(16))... not found in chain rounds [\(chainIds)] after refresh")
                        let error = VotingConfigError.roundIdMismatch(
                            configRoundId: configRoundId,
                            chainRoundId: sessions.first?.voteRoundId.hexString ?? ""
                        )
                        state.screenStack = [.configError(error.errorDescription ?? "Voting config is invalid.")]
                        return .none
                    }
                    let computed = VotingServiceConfig.computeProposalsHash(config.proposals)
                    if computed != matchingSession.proposalsHash {
                        logger.error("proposals_hash mismatch: expected=\(matchingSession.proposalsHash.base64EncodedString()) got=\(computed.base64EncodedString())")
                        let error = VotingConfigError.proposalsHashMismatch(
                            expected: matchingSession.proposalsHash,
                            actual: computed
                        )
                        state.screenStack = [.configError(error.errorDescription ?? "Voting config is invalid.")]
                        return .none
                    }

                    // Binding succeeded. Reset the one-shot retry flag so a later round
                    // transition in this session can still get its own auto-retry attempt.
                    state.hasAttemptedConfigRefresh = false
                }

                // Sort by created_at_height ascending for reliable creation order
                let sorted = sessions.sorted { $0.createdAtHeight < $1.createdAtHeight }
                state.allRounds = sorted.enumerated().map { index, session in
                    State.RoundListItem(roundNumber: index + 1, session: session)
                }

                // Populate voteRecords from persisted UserDefaults so the polls
                // list can render the Voted pill and "X of Y voted" indicator
                // for rounds the user has already confirmed in. Per-round, sync
                // read — fast even for tens of rounds.
                let walletId = state.walletId
                var loadedRecords: [String: VoteRecord] = [:]
                for item in state.allRounds {
                    if let record = Self.loadVoteRecord(walletId: walletId, roundId: item.id) {
                        loadedRecords[item.id] = record
                    }
                }
                state.voteRecords = loadedRecords

                // Always land on the polls list when there are any rounds, so the
                // user explicitly chooses which one to enter — even if there's only
                // one. Empty case still shows the noRounds empty state. Guards
                // against onAppear re-firing while the user is mid-vote.
                if state.allRounds.isEmpty {
                    state.screenStack = [.noRounds]
                } else if state.activeSession == nil {
                    state.screenStack = [.pollsList]
                }
                return .none

            case .roundTapped(let roundId):
                guard let item = state.allRounds.first(where: { $0.id == roundId }) else { return .none }
                let session = item.session
                state.activeSession = session
                state.roundId = session.voteRoundId.hexString
                state.votingRound = sessionBackedRound(from: session, title: item.title, fallback: state.votingRound)
                state.voteRecord = Self.loadVoteRecord(walletId: state.walletId, roundId: state.roundId)
                reconcileProposalState(&state)

                switch session.status {
                case .active:
                    // Go straight to proposal list — the witness/proof pipeline
                    // runs in the background once voting weight is loaded.
                    state.screenStack = [.pollsList, .proposalList]
                    return .merge(
                        .cancel(id: cancelNewRoundPollingId),
                        .send(.startRoundStatusPolling),
                        // Defer pipeline start so SwiftUI renders the navigation
                        // transition before the reducer processes the pipeline action.
                        .run { send in await send(.startActiveRoundPipeline) }
                    )
                case .tallying:
                    state.screenStack = [.tallying]
                    return .send(.startRoundStatusPolling)
                case .finalized:
                    state.screenStack = [.results]
                    return .merge(
                        .send(.fetchTallyResults),
                        .send(.startNewRoundPolling)
                    )
                case .unspecified:
                    return .none
                }

            // MARK: - Initialization

            case .initialize:
                // Guard against onAppear re-firing while already initialized
                guard state.currentScreen == .loading else { return .none }
                // Reset the one-shot auto-retry gate so a cold re-entry into voting
                // (e.g. after dismissing from .configError) gets its own retry allotment
                // instead of inheriting a stuck-true flag from the prior session.
                state.hasAttemptedConfigRefresh = false
                return .run { [votingAPI] send in
                    // 1. Fetch service config (local override → CDN). Decode or version failures
                    //    surface as VotingConfigError and block the voting feature entirely;
                    //    the wallet must be updated before the user can proceed.
                    let config = try await votingAPI.fetchServiceConfig()
                    await send(.serviceConfigLoaded(config))
                } catch: { error, send in
                    logger.error("Service config unavailable: \(error)")
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    await send(.configUnsupported(message))
                }

            case .configUnsupported(let message):
                state.screenStack = [.configError(message)]
                return .none

            case .serviceConfigLoaded(let config):
                state.serviceConfig = config
                let walletId = state.walletId
                return .run { [votingAPI, votingCrypto] send in
                    // 2. Configure API client URLs
                    await votingAPI.configureURLs(config)

                    // 3. Open voting database and scope to current wallet
                    let dbPath = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("voting.sqlite3").path
                    try await votingCrypto.openDatabase(dbPath)
                    try await votingCrypto.setWalletId(walletId)

                    // 4. Fetch all rounds and populate the list
                    let allRounds = try await votingAPI.fetchAllRounds()
                    logger.info("Fetched \(allRounds.count) rounds")
                    for round in allRounds {
                        logger.debug(
                            "round=\(round.voteRoundId.hexString.prefix(16))... status=\(round.status.rawValue) snapshot=\(round.snapshotHeight)"
                        )
                    }

                    await send(.allRoundsLoaded(allRounds))
                } catch: { error, send in
                    logger.error("Initialization failed: \(error)")
                    await send(.initializeFailed(error.localizedDescription))
                }

            case .startActiveRoundPipeline:
                guard let session = state.activeSession, session.status == .active else { return .none }
                let network = zcashSDKEnvironment.network
                let walletDbPath = databaseFiles.dataDbURLFor(network).path
                let networkId: UInt32 = network.networkType == .mainnet ? 0 : 1
                let snapshotHeight = session.snapshotHeight
                let roundId = session.voteRoundId.hexString
                let accountUUID: [UInt8] = state.selectedWalletAccount?.id.id ?? []
                return .run { [votingCrypto, mnemonic, walletStorage, sdkSynchronizer] send in
                    // Check wallet sync progress before querying notes.
                    // The SDK synchronizer may report height 0 briefly on a
                    // fresh app launch before it hydrates its persisted state.
                    // Retry a few times to avoid a false "not synced" screen.
                    var walletScannedHeight = UInt64(sdkSynchronizer.latestState().latestBlockHeight)
                    if walletScannedHeight == 0 {
                        for _ in 0..<5 {
                            try await Task.sleep(for: .seconds(1))
                            walletScannedHeight = UInt64(sdkSynchronizer.latestState().latestBlockHeight)
                            if walletScannedHeight > 0 { break }
                        }
                    }
                    if walletScannedHeight < snapshotHeight {
                        logger.info("Wallet scanned to \(walletScannedHeight), snapshot at \(snapshotHeight) — not synced yet")
                        await send(.walletNotSynced(scannedHeight: walletScannedHeight, snapshotHeight: snapshotHeight))
                        return
                    }

                    let notes = try await votingCrypto.getWalletNotes(
                        walletDbPath,
                        snapshotHeight,
                        networkId,
                        accountUUID
                    )
                    let totalWeight = notes.reduce(UInt64(0)) { $0 + $1.value }
                    logger.info("Loaded \(notes.count) notes at height \(snapshotHeight), total weight: \(totalWeight)")
                    await send(.votingWeightLoaded(totalWeight, notes))

                    // Load or generate voting hotkey mnemonic, derive address for UI
                    do {
                        let phrase: String
                        if let stored = try? walletStorage.exportVotingHotkey() {
                            phrase = stored.seedPhrase.value()
                        } else {
                            phrase = try mnemonic.randomMnemonic()
                            try walletStorage.importVotingHotkey(phrase)
                        }
                        let seed = try mnemonic.toSeed(phrase)
                        let hotkey = try await votingCrypto.generateHotkey(roundId, seed)
                        logger.debug("Hotkey address: \(hotkey.address)")
                        await send(.hotkeyLoaded(hotkey.address))
                    } catch {
                        logger.error("Failed to generate hotkey: \(error)")
                    }
                } catch: { error, send in
                    logger.error("Active round pipeline failed: \(error)")
                    await send(.initializeFailed(error.localizedDescription))
                }
                .cancellable(id: cancelPipelineId, cancelInFlight: true)

            case .activeSessionLoaded(let session):
                state.activeSession = session
                state.roundId = session.voteRoundId.hexString
                state.votingRound = sessionBackedRound(from: session, title: state.votingRound.title, fallback: state.votingRound)
                reconcileProposalState(&state)
                let roundPrefix = session.voteRoundId.hexString.prefix(16)
                logger.info("activeSessionLoaded: status=\(session.status.rawValue) round=\(roundPrefix)... proposals=\(session.proposals.count)")
                return .none

            case .noActiveRound:
                state.activeSession = nil
                state.screenStack = [.noRounds]
                return .none

            case let .votingWeightLoaded(weight, notes):
                state.walletNotes = notes
                if notes.isEmpty {
                    state.votingWeight = 0
                    state.ineligibilityReason = .noNotes
                    state.screenStack = [.ineligible]
                    return .none
                }
                // Use smart bundling to determine eligible weight (excluding dust bundles)
                let bundleResult = notes.smartBundles()
                let eligibleWeight = bundleResult.eligibleWeight
                state.votingWeight = eligibleWeight
                if bundleResult.droppedCount > 0 {
                    let dropped = bundleResult.droppedCount
                    logger.info("Smart bundling: dropped \(dropped) notes in sub-threshold bundles (eligible: \(eligibleWeight) of \(weight) total)")
                }
                if eligibleWeight < ballotDivisor {
                    state.ineligibilityReason = .balanceTooLow
                    state.screenStack = [.ineligible]
                    return .none
                }
                // Show proposals immediately while witnesses load in the background.
                // For Keystone users that haven't authorized yet, go straight to the
                // delegation signing screen to avoid a brief flash of the proposal list.
                // Don't set delegationProofStatus here — verifyWitnesses will set it
                // only for fresh rounds, avoiding a brief flash for cached rounds.
                // Restore persisted draft votes (survives app termination)
                let restored = Self.loadDrafts(walletId: state.walletId, roundId: state.roundId)
                // Only keep drafts for proposals that haven't been submitted yet
                state.draftVotes = restored.filter { state.votes[$0.key] == nil }
                if !state.draftVotes.isEmpty {
                    let draftCount = state.draftVotes.count
                    logger.info("Restored \(draftCount) persisted draft votes")
                }

                state.screenStack = [.pollsList, .proposalList]
                return .merge(
                    .publisher {
                        votingCrypto.stateStream()
                            .receive(on: DispatchQueue.main)
                            .map(Action.votingDbStateChanged)
                    }
                    .cancellable(id: cancelStateStreamId, cancelInFlight: true),
                    .send(.verifyWitnesses)
                )

            case .initializeFailed(let error):
                logger.error("Initialization error: \(error)")
                state.screenStack = [.error(VotingErrorMapper.userFriendlyMessage(from: error))]
                return .none

            case let .walletNotSynced(scannedHeight, snapshotHeight):
                state.walletScannedHeight = scannedHeight
                state.screenStack = [.walletSyncing]
                // Poll sync progress and auto-retry the pipeline once caught up
                return .run { [sdkSynchronizer] send in
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(2))
                        let height = UInt64(sdkSynchronizer.latestState().latestBlockHeight)
                        await send(.walletSyncProgressUpdated(height))
                        if height >= snapshotHeight {
                            await send(.startActiveRoundPipeline)
                            return
                        }
                    }
                } catch: { _, _ in }
                .cancellable(id: cancelPipelineId, cancelInFlight: true)

            case .walletSyncProgressUpdated(let height):
                state.walletScannedHeight = height
                return .none

            case .hotkeyLoaded(let address):
                state.hotkeyAddress = address
                return .none

            // MARK: - Round Status Polling

            case .startRoundStatusPolling:
                guard let session = state.activeSession else { return .none }
                let roundIdHex = session.voteRoundId.hexString
                return .run { [votingAPI] send in
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(5))
                        let updated = try await votingAPI.fetchRoundById(roundIdHex)
                        await send(.roundStatusUpdated(roundId: updated.voteRoundId, updated.status))
                    }
                } catch: { error, _ in
                    logger.error("Status polling error: \(error)")
                }
                .cancellable(id: cancelStatusPollingId, cancelInFlight: true)

            case let .roundStatusUpdated(polledRoundId, newStatus):
                guard let session = state.activeSession else { return .none }

                // Guard against stale poll responses from a previously viewed
                // round arriving after the user navigated to a different round.
                // TCA effect cancellation is cooperative, so a queued action
                // from the old poll can slip through.
                guard polledRoundId == session.voteRoundId else {
                    let polledPrefix = polledRoundId.hexString.prefix(16)
                    let activePrefix = session.voteRoundId.hexString.prefix(16)
                    logger.debug("roundStatusUpdated: ignoring stale poll for \(polledPrefix)..., active round is \(activePrefix)...")
                    return .none
                }

                // Only react to actual transitions
                logger.info("roundStatusUpdated: old=\(session.status.rawValue) new=\(newStatus.rawValue)")
                guard newStatus != session.status else { return .none }

                // Update session status
                let updatedSession = VotingSession(
                    voteRoundId: session.voteRoundId,
                    snapshotHeight: session.snapshotHeight,
                    snapshotBlockhash: session.snapshotBlockhash,
                    proposalsHash: session.proposalsHash,
                    voteEndTime: session.voteEndTime,
                    ceremonyStart: session.ceremonyStart,
                    eaPK: session.eaPK,
                    vkZkp1: session.vkZkp1,
                    vkZkp2: session.vkZkp2,
                    vkZkp3: session.vkZkp3,
                    ncRoot: session.ncRoot,
                    nullifierIMTRoot: session.nullifierIMTRoot,
                    creator: session.creator,
                    description: session.description,
                    discussionURL: session.discussionURL,
                    proposals: session.proposals,
                    status: newStatus,
                    createdAtHeight: session.createdAtHeight,
                    title: session.title
                )
                state.activeSession = updatedSession

                // Also update the corresponding entry in allRounds so the list stays consistent
                if let idx = state.allRounds.firstIndex(where: { $0.session.voteRoundId == session.voteRoundId }) {
                    state.allRounds[idx] = State.RoundListItem(
                        roundNumber: state.allRounds[idx].roundNumber,
                        session: updatedSession
                    )
                }

                switch newStatus {
                case .tallying:
                    state.screenStack = [.tallying]
                    return .none
                case .finalized:
                    state.screenStack = [.results]
                    return .merge(
                        .cancel(id: cancelStatusPollingId),
                        .send(.fetchTallyResults),
                        .send(.startNewRoundPolling)
                    )
                default:
                    return .none
                }

            // MARK: - New Round Polling (after finalization)

            case .startNewRoundPolling:
                return .run { [votingAPI] send in
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(30))
                        let allRounds = try await votingAPI.fetchAllRounds()
                        let hasActive = allRounds.contains { $0.status == .active || $0.status == .tallying }
                        if hasActive {
                            await send(.allRoundsLoaded(allRounds))
                        }
                    }
                } catch: { _, _ in }
                .cancellable(id: cancelNewRoundPollingId, cancelInFlight: true)

            // MARK: - Tally Results

            case .fetchTallyResults:
                guard let session = state.activeSession else { return .none }
                state.isLoadingTallyResults = true
                let roundIdHex = session.voteRoundId.hexString
                return .run { [votingAPI] send in
                    let results = try await votingAPI.fetchTallyResults(roundIdHex)
                    await send(.tallyResultsLoaded(results))
                } catch: { error, send in
                    logger.error("Failed to fetch tally results: \(error)")
                    await send(.tallyResultsLoaded([:]))
                }

            case .tallyResultsLoaded(let results):
                state.tallyResults = results
                state.isLoadingTallyResults = false
                return .none

            // MARK: - Share Confirmation Polling

            // MARK: - Share Info Sheet

            case .showShareInfo(let proposalId):
                state.shareInfoProposalId = proposalId
                state.showShareInfoSheet = true
                return .none

            case .hideShareInfo:
                state.showShareInfoSheet = false
                state.shareInfoProposalId = nil
                return .none

            // MARK: - Governance Tab Lifecycle

            case .governanceTabAppeared:
                guard state.activeSession != nil else { return .none }
                guard !state.isSubmittingVote else { return .none }
                guard !state.votes.isEmpty else { return .none }

                state.shareTrackingStatus = .loading
                return .send(.loadShareDelegations)

            case .governanceTabDisappeared:
                state.shareTrackingStatus = .idle
                return .cancel(id: cancelShareTrackingId)

            // MARK: - Share Delegation Tracking (DB-backed)

            case .loadShareDelegations:
                return .run { [roundId = state.votingRound.id, votingCrypto] send in
                    let delegations = try await votingCrypto.getShareDelegations(roundId)
                    await send(.shareDelegationsLoaded(delegations))
                } catch: { error, _ in
                    // Share tracking is non-critical — silently degrade
                    logger.error("Failed to load share delegations: \(error)")
                }

            case .shareDelegationsLoaded(let delegations):
                state.shareDelegations = delegations
                let allConfirmed = !delegations.isEmpty && delegations.allSatisfy(\.confirmed)
                if delegations.isEmpty {
                    state.shareTrackingStatus = .idle
                } else if allConfirmed {
                    state.shareTrackingStatus = .fullyConfirmed
                } else {
                    state.shareTrackingStatus = .tracking
                    // Start the single poll loop
                    return .run { send in
                        try await Task.sleep(for: .seconds(1))
                        await send(.pollShareStatus)
                    }
                    .cancellable(id: cancelShareTrackingId, cancelInFlight: true)
                }
                return .none

            case .shareDelegationsRefreshed(let delegations):
                // Update state only — called from the poll loop. Does NOT start a new poll.
                state.shareDelegations = delegations
                let allConfirmed = !delegations.isEmpty && delegations.allSatisfy(\.confirmed)
                if delegations.isEmpty {
                    state.shareTrackingStatus = .idle
                } else if allConfirmed {
                    state.shareTrackingStatus = .fullyConfirmed
                } else {
                    state.shareTrackingStatus = .tracking
                }
                return .none

            case .pollShareStatus:
                guard state.shareTrackingStatus == .tracking else { return .none }
                return .run { [
                    roundId = state.votingRound.id,
                    voteServers = state.serviceConfig?.voteServers ?? [],
                    votes = state.votes,
                    proposals = state.votingRound.proposals,
                    singleShare = state.activeSession?.isLastMoment ?? false,
                    voteEndTime = UInt64(state.activeSession?.voteEndTime.timeIntervalSince1970 ?? 0),
                    votingAPI, votingCrypto
                ] send in
                    // Load fresh delegations from DB so we don't re-query already-confirmed shares.
                    let freshDelegations = (try? await votingCrypto.getShareDelegations(roundId)) ?? []
                    let confirmed = freshDelegations.filter(\.confirmed).count
                    let unconfirmed = freshDelegations.filter { !$0.confirmed }
                    let now = UInt64(Date().timeIntervalSince1970)

                    logger.debug("[SharePoll] total=\(freshDelegations.count) confirmed=\(confirmed) unconfirmed=\(unconfirmed.count)")

                    // Track shares that need resubmission (still pending after overdue threshold)
                    struct ResubmitCandidate {
                        let share: VotingShareDelegation
                        let proposalId: UInt32
                        let bundleIndex: UInt32
                    }
                    var resubmitQueue: [ResubmitCandidate] = []

                    // Check confirmation status of shares past their submitAt.
                    // Wait until submitAt + 10s before first check — gives the helper server
                    // time to process and submit the share on-chain.
                    let checkGrace: UInt64 = 10
                    let readyShares = unconfirmed.filter { share in
                        let readyAt = share.submitAt > 0 ? share.submitAt + checkGrace : 0
                        return now >= readyAt
                    }
                    let futureCount = unconfirmed.count - readyShares.count

                    logger.debug("[SharePoll] ready=\(readyShares.count) future=\(futureCount)")

                    if let helperURL = voteServers.first?.url {
                        var newlyConfirmed = 0
                        for share in readyShares {
                            let nullifierHex = share.nullifier.map { String(format: "%02x", $0) }.joined()
                            do {
                                let result = try await votingAPI.fetchShareStatus(helperURL, roundId, nullifierHex)
                                if result == .confirmed {
                                    try await votingCrypto.markShareConfirmed(
                                        roundId, share.bundleIndex, share.proposalId, share.shareIndex
                                    )
                                    newlyConfirmed += 1
                                } else if share.submitAt > 0 {
                                    // Adaptive overdue threshold: wait 25% of the share's
                                    // remaining window after submitAt before resubmitting,
                                    // clamped to [30s, 3600s]. Lets resubmission fire within
                                    // a normal round (e.g. 15-min round → 30–200 s) instead of
                                    // a fixed 1 h threshold, which was always past voteEndTime
                                    // and so never saved a round where a helper silently
                                    // dropped shares at its broadcast step.
                                    let remainingAtSubmit = voteEndTime > share.submitAt
                                        ? voteEndTime - share.submitAt : 0
                                    let overdueThreshold: UInt64 = max(30, min(3600, remainingAtSubmit / 4))
                                    // Skip resubmission if the round is already closing — chain
                                    // rejects MsgRevealShare after voteEndTime, so a resubmit
                                    // would only waste a POST and noise the log.
                                    let resubmitCutoff: UInt64 = 10
                                    if now >= share.submitAt + overdueThreshold,
                                       voteEndTime > now + resubmitCutoff {
                                        resubmitQueue.append(ResubmitCandidate(
                                            share: share,
                                            proposalId: share.proposalId,
                                            bundleIndex: share.bundleIndex
                                        ))
                                    }
                                }
                            } catch {
                                // On error, skip remaining shares this cycle
                                logger.warning("Share status check failed for share \(share.shareIndex): \(error)")
                                break
                            }
                        }
                        if !readyShares.isEmpty {
                            logger.debug("[SharePoll] queried=\(readyShares.count) newlyConfirmed=\(newlyConfirmed)")
                        }
                    }

                    // Phase 2: Resubmit overdue pending shares
                    // Group by (bundleIndex, proposalId) to rebuild payloads once per group
                    let grouped = Dictionary(grouping: resubmitQueue) { "\($0.bundleIndex):\($0.proposalId)" }
                    for (_, candidates) in grouped {
                        guard let first = candidates.first else { continue }
                        let bundleIndex = first.bundleIndex
                        let proposalId = first.proposalId

                        // Rebuild share payloads from the stored commitment bundle (includes vcTreePosition)
                        guard let result = try? await votingCrypto.getVoteCommitmentBundleWithPosition(roundId, bundleIndex, proposalId),
                              let choice = votes[proposalId]
                        else { continue }
                        let savedBundle = result.bundle
                        let vcTreePosition = result.vcTreePosition
                        let numOptions = UInt32(proposals.first { $0.id == proposalId }?.options.count ?? 3)

                        do {
                            var payloads = try await votingCrypto.buildSharePayloads(
                                savedBundle.encShares, savedBundle, choice, numOptions,
                                vcTreePosition, singleShare
                            )
                            // Set submit_at to 0 (immediate) for resubmission
                            for i in payloads.indices {
                                payloads[i].submitAt = 0
                            }

                            // Resubmit only the shares that are overdue
                            for candidate in candidates {
                                guard let payload = payloads.first(where: {
                                    $0.encShare.shareIndex == candidate.share.shareIndex
                                }) else { continue }

                                let excludeURLs = candidate.share.sentToURLs
                                let newServers = try await votingAPI.resubmitShare(payload, roundId, excludeURLs)

                                if !newServers.isEmpty {
                                    // Record the new servers in DB
                                    try await votingCrypto.addSentServers(
                                        roundId, bundleIndex, proposalId,
                                        candidate.share.shareIndex, newServers
                                    )
                                    logger.info("Resubmitted share \(candidate.share.shareIndex) to \(newServers.count) new server(s)")
                                }
                            }
                        } catch {
                            logger.warning("Share resubmission failed for bundle \(bundleIndex), proposal \(proposalId): \(error)")
                        }
                    }

                    // Reload fresh state from DB and update the UI (without starting a new poll)
                    let updatedDelegations = (try? await votingCrypto.getShareDelegations(roundId)) ?? freshDelegations
                    await send(.shareDelegationsRefreshed(updatedDelegations))

                    // Schedule next poll: sleep until the next share is ready to check.
                    let refreshedNow = UInt64(Date().timeIntervalSince1970)
                    let stillUnconfirmed = updatedDelegations.filter { !$0.confirmed }

                    // Find the soonest unconfirmed share's check time (submitAt + grace)
                    let futureCheckTimes = stillUnconfirmed.compactMap { share -> UInt64? in
                        let readyAt = share.submitAt > 0 ? share.submitAt + checkGrace : 0
                        return readyAt > refreshedNow ? readyAt : nil
                    }

                    let sleepSeconds: UInt64
                    if stillUnconfirmed.isEmpty {
                        logger.debug("[SharePoll] all confirmed, stopping poll")
                        return
                    } else if let soonest = futureCheckTimes.min() {
                        sleepSeconds = min(soonest - refreshedNow, 30)
                    } else {
                        sleepSeconds = 15
                    }

                    let actualSleep = max(sleepSeconds, 3)
                    logger.debug("[SharePoll] sleeping \(actualSleep)s (stillUnconfirmed=\(stillUnconfirmed.count) futureShares=\(futureCheckTimes.count))")
                    try await Task.sleep(for: .seconds(actualSleep))
                    await send(.pollShareStatus)
                } catch: { _, _ in }
                .cancellable(id: cancelShareTrackingId, cancelInFlight: true)


            // MARK: - Witness Verification

            case .verifyWitnesses:
                guard let activeSession = state.activeSession else {
                    state.witnessStatus = .failed(VotingErrorMapper.userFriendlyMessage(from: "missing active session"))
                    return .none
                }
                state.witnessTiming = nil
                let roundId = activeSession.voteRoundId.hexString
                let snapshotHeight = activeSession.snapshotHeight
                let notes = state.walletNotes
                let network = zcashSDKEnvironment.network
                let walletDbPath = databaseFiles.dataDbURLFor(network).path
                return .run { [sdkSynchronizer, votingCrypto, votingAPI] send in
                    // Check if this round already exists and ALL bundles have proofs
                    let existingState = try? await votingCrypto.getRoundState(roundId)
                    let alreadyAuthorized = existingState?.proofGenerated ?? false

                    if alreadyAuthorized {
                        await send(.roundResumeChecked(alreadyAuthorized: true))
                        return
                    }

                    // --- Crash recovery: check if some delegation TXs already landed on-chain ---
                    let existingBundleCount = (try? await votingCrypto.getBundleCount(roundId)) ?? 0

                    var recoveredDelegationHashes: [(UInt32, String)] = []
                    for bundleIndex: UInt32 in 0..<existingBundleCount {
                        if let txHash = try? await votingCrypto.getDelegationTxHash(roundId, bundleIndex) {
                            recoveredDelegationHashes.append((bundleIndex, txHash))
                        }
                    }

                    if !recoveredDelegationHashes.isEmpty {
                        var recoveredPositions: [UInt32: UInt32] = [:]
                        for (bundleIndex, txHash) in recoveredDelegationHashes {
                            if let confirmation = try? await votingAPI.fetchTxConfirmation(txHash),
                               confirmation.code == 0,
                               let leafValue = confirmation.event(ofType: "delegate_vote")?.attribute(forKey: "leaf_index"),
                               let vanPosition = UInt32(leafValue) {
                                try? await votingCrypto.storeVanPosition(roundId, bundleIndex, vanPosition)
                                recoveredPositions[bundleIndex] = vanPosition
                            }
                        }

                        if existingBundleCount > 0 && UInt32(recoveredPositions.count) >= existingBundleCount {
                            try await votingCrypto.clearRecoveryState(roundId)
                            await send(.roundResumeChecked(alreadyAuthorized: true))
                            return
                        } else if !recoveredPositions.isEmpty {
                            await send(.witnessPreparationStarted)
                            let count = try await votingCrypto.getBundleCount(roundId)
                            await send(.witnessVerificationCompleted([], [], .init(treeStateFetchMs: 0, witnessGenerationMs: 0, verificationMs: 0), count))
                            return
                        }
                    }

                    await send(.witnessPreparationStarted)

                    try? await votingCrypto.clearRound(roundId)
                    try await votingCrypto.clearRecoveryState(roundId)
                    let params = VotingRoundParams(
                        voteRoundId: activeSession.voteRoundId,
                        snapshotHeight: snapshotHeight,
                        eaPK: activeSession.eaPK,
                        ncRoot: activeSession.ncRoot,
                        nullifierIMTRoot: activeSession.nullifierIMTRoot
                    )
                    try await votingCrypto.initRound(params, nil)

                    // Skip witness pipeline if wallet has no notes at snapshot height
                    guard !notes.isEmpty else {
                        let emptyTiming = Voting.State.WitnessTiming(
                            treeStateFetchMs: 0,
                            witnessGenerationMs: 0,
                            verificationMs: 0
                        )
                        await send(.witnessVerificationCompleted([], [], emptyTiming, 0))
                        return
                    }

                    // Setup bundles (value-aware split into groups of up to 5)
                    let setupResult = try await votingCrypto.setupBundles(roundId, notes)
                    let bundleCount = setupResult.bundleCount
                    logger.info("Setup \(bundleCount) bundle(s) for \(notes.count) notes (eligible weight: \(setupResult.eligibleWeight))")

                    // Phase 1: Fetch tree state from lightwalletd
                    let fetchStart = ContinuousClock.now
                    let treeStateBytes = try await sdkSynchronizer.getTreeState(snapshotHeight)
                    try await votingCrypto.storeTreeState(roundId, treeStateBytes)
                    let fetchEnd = ContinuousClock.now
                    let fetchMs = UInt64(fetchStart.duration(to: fetchEnd).components.seconds * 1000)
                        + UInt64(fetchStart.duration(to: fetchEnd).components.attoseconds / 1_000_000_000_000_000)
                    logger.debug("Tree state fetch: \(fetchMs)ms")

                    // Phase 2: Generate witnesses per-bundle (includes Rust-side verification)
                    let noteChunks = notes.smartBundles().bundles
                    var allWitnesses: [WitnessData] = []
                    for bundleIndex in 0..<bundleCount {
                        let chunkNotes = noteChunks[Int(bundleIndex)]
                        let witnesses = try await votingCrypto.generateNoteWitnesses(
                            roundId, bundleIndex, walletDbPath, chunkNotes
                        )
                        allWitnesses.append(contentsOf: witnesses)
                    }
                    let genEnd = ContinuousClock.now
                    let genMs = UInt64(fetchEnd.duration(to: genEnd).components.seconds * 1000)
                        + UInt64(fetchEnd.duration(to: genEnd).components.attoseconds / 1_000_000_000_000_000)
                    logger.debug("Witness generation: \(genMs)ms (\(allWitnesses.count) notes)")

                    // Phase 3: Verify each witness on Swift side for UI display
                    let sortedNotes = noteChunks.flatMap { $0 }
                    var results: [Voting.State.NoteWitnessResult] = []
                    for (idx, witness) in allWitnesses.enumerated() {
                        let verified = (try? await votingCrypto.verifyWitness(witness)) ?? false
                        let note = sortedNotes[idx]
                        results.append(.init(position: note.position, value: note.value, verified: verified))
                        logger.debug("Note pos=\(note.position) value=\(note.value) verified=\(verified)")
                    }
                    let verifyEnd = ContinuousClock.now
                    let verifyMs = UInt64(genEnd.duration(to: verifyEnd).components.seconds * 1000)
                        + UInt64(genEnd.duration(to: verifyEnd).components.attoseconds / 1_000_000_000_000_000)
                    logger.debug("Swift verification: \(verifyMs)ms")
                    logger.info("Total witness pipeline: \(fetchMs + genMs + verifyMs)ms")

                    let timing = Voting.State.WitnessTiming(
                        treeStateFetchMs: fetchMs,
                        witnessGenerationMs: genMs,
                        verificationMs: verifyMs
                    )
                    await send(.witnessVerificationCompleted(results, allWitnesses, timing, bundleCount))
                } catch: { error, send in
                    logger.error("Witness verification failed: \(error)")
                    await send(.witnessVerificationFailed(error.localizedDescription))
                }

            case .witnessPreparationStarted:
                // Only shown for fresh rounds (not cached). This avoids a brief
                // flash of "Preparing note witnesses..." when resuming a round.
                state.witnessStatus = .inProgress
                state.delegationProofStatus = .generating(progress: 0)
                return .none

            case .rerunWitnessVerification:
                // Invalidate cached witnesses and re-run from scratch
                state.noteWitnessResults = []
                state.cachedWitnesses = []
                state.witnessTiming = nil
                return .send(.verifyWitnesses)

            case let .witnessVerificationCompleted(results, witnesses, timing, bundleCount):
                state.noteWitnessResults = results
                state.cachedWitnesses = witnesses
                state.witnessTiming = timing
                state.witnessStatus = .completed
                state.bundleCount = bundleCount
                // If bundles were previously skipped, the DB count is less than the
                // total from smartBundles(). Recalculate votingWeight to reflect only
                // the kept bundles (quantized per bundle).
                let allBundles = state.walletNotes.smartBundles().bundles
                if bundleCount > 0, Int(bundleCount) < allBundles.count {
                    state.votingWeight = (0..<Int(bundleCount)).reduce(UInt64(0)) { total, i in
                        let raw = allBundles[i].reduce(UInt64(0)) { $0 + $1.value }
                        return total + quantizeWeight(raw)
                    }
                }
                // Delegation (ZKP #1) is deferred until the user submits their vote.
                // Witnesses are ready; delegation will use them at submission time.
                return .none

            case .witnessVerificationFailed(let error):
                let message = VotingErrorMapper.userFriendlyMessage(from: error)
                state.witnessStatus = .failed(message)
                state.delegationProofStatus = .failed(message)
                state.isDelegationProofInFlight = false
                return .none

            // MARK: - Round Resume

            case .roundResumeChecked(let alreadyAuthorized):
                if alreadyAuthorized {
                    state.delegationProofStatus = .complete
                    state.screenStack = [.pollsList, .proposalList]
                    state.witnessStatus = .completed
                    // Restore bundleCount from the DB so vote casting knows how many bundles to iterate.
                    // Start state stream to sync votes and hotkey from the existing round,
                    // then trigger a refresh so the current DB state is published
                    // (stateStream uses dropFirst, so without this the existing value is lost).
                    let roundId = state.roundId
                    return .merge(
                        .run { [votingCrypto] send in
                            let count = try await votingCrypto.getBundleCount(roundId)
                            await send(.bundleCountRestored(count))
                        } catch: { error, send in
                            logger.error("Failed to restore bundle count: \(error)")
                            await send(.witnessVerificationFailed("Failed to restore voting state: \(error.localizedDescription)"))
                        },
                        .publisher {
                            votingCrypto.stateStream()
                                .receive(on: DispatchQueue.main)
                                .map(Action.votingDbStateChanged)
                        }
                        .cancellable(id: cancelStateStreamId, cancelInFlight: true),
                        .run { _ in
                            await votingCrypto.refreshState(roundId)
                        }
                    )
                }
                return .none

            case .bundleCountRestored(let count):
                state.bundleCount = count
                // If bundles were previously skipped, the DB count is less than the
                // total from smartBundles(). Recalculate votingWeight to reflect only
                // the kept bundles (quantized per bundle).
                let allBundles = state.walletNotes.smartBundles().bundles
                if count > 0, Int(count) < allBundles.count {
                    state.votingWeight = (0..<Int(count)).reduce(UInt64(0)) { total, i in
                        let raw = allBundles[i].reduce(UInt64(0)) { $0 + $1.value }
                        return total + quantizeWeight(raw)
                    }
                }
                let roundId = state.roundId
                let bundleCount = count
                return .run { [votingCrypto] send in
                    let votes = (try? await votingCrypto.getVotes(roundId)) ?? []

                    // Check 1: a TX hash exists but the vote isn't marked as submitted
                    // in the DB yet (crash during step 2 or 3 of a bundle).
                    // Add the vote to draftVotes and let submitAllDrafts handle recovery.
                    let unsubmitted = votes.filter { !$0.submitted }
                    for vote in unsubmitted {
                        if let _ = try? await votingCrypto.getVoteTxHash(roundId, vote.bundleIndex, vote.proposalId) {
                            logger.info("Vote resume: found in-flight vote for proposal \(vote.proposalId), auto-resuming via batch path")
                            await send(.setDraftVote(proposalId: vote.proposalId, choice: vote.choice))
                            await send(.submitAllDrafts)
                            return
                        }
                    }

                    // Check 2: partial vote — some bundles submitted, but fewer
                    // VoteRecords than bundleCount (crash before a later bundle's
                    // buildVoteCommitment created a VoteRecord).
                    if bundleCount > 1 {
                        var byProposal: [UInt32: (submitted: Int, total: Int, choice: VoteChoice)] = [:]
                        for vote in votes {
                            var entry = byProposal[vote.proposalId] ?? (submitted: 0, total: 0, choice: vote.choice)
                            entry.total += 1
                            if vote.submitted { entry.submitted += 1 }
                            byProposal[vote.proposalId] = entry
                        }
                        for (proposalId, info) in byProposal {
                            if info.submitted > 0, info.total < Int(bundleCount) {
                                logger.info("Vote resume: proposal \(proposalId) has \(info.total)/\(bundleCount) bundle records, resuming via batch path")
                                await send(.setDraftVote(proposalId: proposalId, choice: info.choice))
                                await send(.submitAllDrafts)
                                return
                            }
                        }
                    }
                }

            // MARK: - DB State Stream

            case .votingDbStateChanged(let dbState):
                // Votes: DB is source of truth, but preserve optimistic vote during submission
                var mergedVotes = dbState.votesByProposal
                if state.isSubmittingVote {
                    for (proposalId, choice) in state.votes where mergedVotes[proposalId] == nil {
                        mergedVotes[proposalId] = choice
                    }
                }
                state.votes = mergedVotes
                // Proof status: if DB says proof succeeded and we're not actively generating, sync it
                if dbState.roundState.proofGenerated && state.delegationProofStatus != .complete {
                    state.delegationProofStatus = .complete
                }
                // Sync hotkey address from DB if available
                if let addr = dbState.roundState.hotkeyAddress {
                    state.hotkeyAddress = addr
                }
                logger.debug("DB state: phase=\(String(describing: dbState.roundState.phase)), \(dbState.votes.count) votes")

                // If votes arrived and share tracking hasn't started yet, kick it off.
                // This handles cold start where governanceTabAppeared fires before votes are loaded.
                // Don't start while a vote is actively being submitted — the share delegation
                // rows are written at the end of submission, so polling mid-submission shows
                // a flickering empty/partial bar.
                if !state.votes.isEmpty && state.shareTrackingStatus == .idle
                    && !state.isSubmittingVote {
                    state.shareTrackingStatus = .loading
                    return .send(.loadShareDelegations)
                }
                // Don't re-trigger if already tracking — the poll loop handles refresh.
                return .none

            // MARK: - Delegation Signing

            case .copyHotkeyAddress:
                if let address = state.hotkeyAddress {
                    pasteboard.setString(address.redacted)
                    state.$toast.withLock { $0 = .top(String(localizable: .generalCopiedToTheClipboard)) }
                }
                return .none

            case .delegationApproved:
                // User is already on the proposal list; delegation signing screen
                // was pushed on top. Just trigger the proof pipeline.
                return .send(.startDelegationProof)

            case .delegationRejected:
                state.pendingGovernancePczt = nil
                state.pendingUnsignedDelegationPczt = nil
                state.keystoneSigningStatus = .idle
                state.keystoneBundleSignatures = []
                state.isDelegationProofInFlight = false
                // Cancel any pending submission that triggered delegation.
                state.pendingBatchSubmission = false
                state.isSubmittingVote = false
                // Pop the delegation signing screen back to proposals.
                if state.screenStack.last == .delegationSigning {
                    state.screenStack.removeLast()
                    return .none
                }
                return .send(.dismissFlow)

            case .retryKeystoneSigning:

                state.pendingGovernancePczt = nil
                state.pendingUnsignedDelegationPczt = nil
                state.keystoneSigningStatus = .idle
                state.currentKeystoneBundleIndex = 0
                state.isDelegationProofInFlight = false
                state.keystoneBundleSignatures = []
                return .send(.startDelegationProof)

            // MARK: - Background ZKP Delegation

            case .startDelegationProof:
                guard !state.isDelegationProofInFlight && state.delegationProofStatus != .complete else {
                    return .none
                }
                state.isDelegationProofInFlight = true
                guard let activeSession = state.activeSession else {
                    return .send(.delegationProofFailed(
                        VotingFlowError.missingActiveSession.localizedDescription
                    ))
                }
                let keystoneMetadata: (seedFingerprint: Data, accountIndex: UInt32)?
                if state.isKeystoneUser {
                    guard
                        let account = state.selectedWalletAccount,
                        let zip32AccountIndex = account.zip32AccountIndex
                    else {
                        return .send(.delegationProofFailed(
                            VotingFlowError.missingSigningAccount.localizedDescription
                        ))
                    }
                    guard
                        let seedFingerprint = account.seedFingerprint,
                        seedFingerprint.count == 32
                    else {
                        return .send(.delegationProofFailed(
                            VotingFlowError.missingSigningAccount.localizedDescription
                        ))
                    }
                    keystoneMetadata = (Data(seedFingerprint), UInt32(zip32AccountIndex.index))
                } else {
                    keystoneMetadata = nil
                }
                if state.isKeystoneUser {
                    state.keystoneSigningStatus = .preparingRequest
                } else {
                    state.delegationProofStatus = .generating(progress: 0)
                }
                let roundId = activeSession.voteRoundId.hexString
                let cachedNotes = state.walletNotes
                let network = zcashSDKEnvironment.network
                let walletDbPath = databaseFiles.dataDbURLFor(network).path
                let networkId: UInt32 = network.networkType == .mainnet ? 0 : 1
                let accountIndex: UInt32 = keystoneMetadata?.accountIndex ?? 0
                let keystoneSeedFingerprint = keystoneMetadata?.seedFingerprint
                let isKeystoneUser = state.isKeystoneUser
                let roundName = state.votingRound.title
                // serviceConfig is guaranteed loaded by the time the user reaches any voting
                // pipeline: the .configError gate in .initialize/.allRoundsLoaded blocks entry
                // to the voting screens when config is missing. The guard is defense-in-depth.
                guard let pirServerUrl = state.serviceConfig?.pirEndpoints.first?.url else {
                    logger.error("serviceConfig unexpectedly nil in startActiveRoundPipeline; aborting")
                    return .none
                }
                let keystoneBundleIndex = state.currentKeystoneBundleIndex
                let bundleCount = state.bundleCount
                return .merge(
                    // Subscribe to DB state stream (follows SDKSynchronizer pattern)
                    .publisher {
                        votingCrypto.stateStream()
                            .receive(on: DispatchQueue.main)
                            .map(Action.votingDbStateChanged)
                    }
                    .cancellable(id: cancelStateStreamId, cancelInFlight: true),
                    // Run delegation proof pipeline
                    // Round is already initialized and witnesses cached by verifyWitnesses
                    .run { [backgroundTask, sdkSynchronizer, votingCrypto, votingAPI, mnemonic, walletStorage] send in
                        let bgTaskId = await backgroundTask.beginTask("Delegation proof generation")
                        do {
                            // Reload hotkey from keychain (generated during initialize)
                            let senderPhrase = try walletStorage.exportWallet().seedPhrase.value()
                            let senderSeed = try mnemonic.toSeed(senderPhrase)
                            let hotkeyPhrase = try walletStorage.exportVotingHotkey().seedPhrase.value()
                            let hotkeySeed = try mnemonic.toSeed(hotkeyPhrase)
                            if isKeystoneUser {
                                guard bundleCount > 0 else {
                                    await backgroundTask.endTask(bgTaskId)
                                    await send(.delegationProofCompleted)
                                    return
                                }
                                // Build governance PCZT for the current bundle — its single Orchard
                                // action IS the governance dummy action, so Keystone's SpendAuth
                                // signature will verify against the PCZT's ZIP-244 sighash.
                                let noteChunks = cachedNotes.smartBundles().bundles
                                let bundleNotes = noteChunks[Int(keystoneBundleIndex)]
                                // Extract Orchard FVK from the note's UFVK so the PCZT uses
                                // Keystone's ak (matching what the ZKP prover derives from the
                                // note's ufvk_str). Without this, rk in the PCZT would be
                                // derived from the app's ak, causing a mismatch (Bug 3 fix).
                                let orchardFvk = try votingCrypto.extractOrchardFvkFromUfvk(
                                    bundleNotes[0].ufvkStr, networkId
                                )
                                logger.info("Keystone: preparing PCZT for bundle \(keystoneBundleIndex + 1)/\(bundleCount)")
                                let govPczt = try await votingCrypto.buildGovernancePczt(
                                    roundId,
                                    keystoneBundleIndex,
                                    bundleNotes,
                                    senderSeed,
                                    hotkeySeed,
                                    networkId,
                                    accountIndex,
                                    roundName,
                                    orchardFvk,
                                    keystoneSeedFingerprint
                                )
                                let redactedPczt = try await sdkSynchronizer
                                    .redactPCZTForSigner(govPczt.pcztBytes)
                                await backgroundTask.endTask(bgTaskId)
                                await send(.keystoneSigningPrepared(govPczt, redactedPczt))
                                return
                            }

                            // Non-Keystone path: delegate using shared pipeline helper.
                            try await Self.runDelegationPipeline(
                                roundId: roundId,
                                cachedNotes: cachedNotes,
                                senderSeed: senderSeed,
                                hotkeySeed: hotkeySeed,
                                networkId: networkId,
                                accountIndex: accountIndex,
                                roundName: roundName,
                                pirServerUrl: pirServerUrl,
                                votingCrypto: votingCrypto,
                                votingAPI: votingAPI,
                                send: send
                            )
                        } catch {
                            await backgroundTask.endTask(bgTaskId)
                            throw error
                        }
                        await backgroundTask.endTask(bgTaskId)
                    } catch: { error, send in
                        if isKeystoneUser {
                            await send(.keystoneSigningFailed(error.localizedDescription))
                        } else {
                            await send(.delegationProofFailed(error.localizedDescription))
                        }
                    }
                )

            case let .keystoneSigningPrepared(govPczt, unsignedPczt):
                state.pendingGovernancePczt = govPczt

                state.pendingUnsignedDelegationPczt = unsignedPczt
                state.keystoneSigningStatus = .awaitingSignature
                return .none

            case .keystoneSigningFailed(let error):
                state.keystoneSigningStatus = .failed(VotingErrorMapper.userFriendlyMessage(from: error))
                return .none

            case .openKeystoneSignatureScan:
                keystoneHandler.resetQRDecoder()
                var scanState = Scan.State.initial
                scanState.instructions = "Scan Keystone QR code\nto sign the transaction"
                scanState.checkers = [.keystoneVotingDelegationPCZTScanChecker]
                state.keystoneScan = scanState
                return .none

            case .keystoneScan(.presented(.foundVotingDelegationPCZT(let signedPczt))):
                state.keystoneScan = nil
                state.keystoneSigningStatus = .parsingSignature
                guard let govPczt = state.pendingGovernancePczt else {
                    return .send(.spendAuthSignatureExtractionFailed(
                        VotingFlowError.missingPendingUnsignedPczt.localizedDescription
                    ))
                }
                let actionIndex = govPczt.actionIndex
                return .run { [votingCrypto] send in
                    let spendAuthSig = try votingCrypto.extractSpendAuthSignatureFromSignedPczt(
                        signedPczt,
                        actionIndex
                    )
                    await send(.spendAuthSignatureExtracted(spendAuthSig, signedPczt))
                } catch: { error, send in
                    await send(.spendAuthSignatureExtractionFailed(error.localizedDescription))
                }

            case .keystoneScan(.presented(.cancelTapped)),
                .keystoneScan(.dismiss):
                state.keystoneScan = nil
                return .none

            case .keystoneScan:
                return .none

            case let .spendAuthSignatureExtracted(keystoneSig, signedPczt):
                guard let rk = state.pendingGovernancePczt?.rk else { // swiftlint:disable:this identifier_name
                    return .send(.delegationProofFailed(
                        VotingFlowError.missingPendingUnsignedPczt.localizedDescription
                    ))
                }

                // Extract ZIP-244 sighash from the signed PCZT synchronously in a
                // lightweight .run so we can store it alongside the sig.
                let bundleCount = state.bundleCount
                let currentIndex = state.currentKeystoneBundleIndex
                return .run { [votingCrypto] send in
                    let keystoneSighash = try votingCrypto.extractPcztSighash(signedPczt)
                    // Store signature for this bundle
                    await send(.keystoneBundleSignatureStored(
                        .init(sig: keystoneSig, sighash: keystoneSighash, rk: rk),
                        bundleIndex: currentIndex,
                        bundleCount: bundleCount
                    ))
                } catch: { error, send in
                    await send(.spendAuthSignatureExtractionFailed(error.localizedDescription))
                }

            case let .keystoneBundleSignatureStored(signature, bundleIndex, bundleCount):
                state.keystoneBundleSignatures.append(signature)
                state.pendingGovernancePczt = nil
                state.pendingUnsignedDelegationPczt = nil

                // Persist to recovery store so signatures survive app restarts
                let roundId = state.roundId
                let sigInfo = KeystoneBundleSignatureInfo(
                    bundleIndex: bundleIndex,
                    sig: signature.sig,
                    sighash: signature.sighash,
                    rk: signature.rk
                )
                let persistEffect: Effect<Action> = .run { [votingCrypto] _ in
                    try await votingCrypto.storeKeystoneBundleSignature(roundId, sigInfo)
                }

                if bundleIndex + 1 < bundleCount {
                    // More bundles to sign — advance index, then auto-start the next bundle's PCZT.
                    state.currentKeystoneBundleIndex += 1
                    state.isDelegationProofInFlight = false
                    state.keystoneSigningStatus = .idle
                    return .merge(persistEffect, .send(.delegationApproved))
                } else {
                    // All bundles signed — pop delegation signing and show the
                    // submission screen with the authorizing progress bar while
                    // the ZKP proof is generated and delegation TX submitted.
                    state.keystoneSigningStatus = .idle
                    state.delegationProofStatus = .generating(progress: 0)
                    state.batchSubmissionStatus = .authorizing
                    if state.screenStack.last == .delegationSigning {
                        state.screenStack.removeLast()
                    }
                    return .merge(persistEffect, .send(.keystoneAllBundlesSigned))
                }

            case .keystoneAllBundlesSigned:
                guard let activeSession = state.activeSession else {
                    return .send(.delegationProofFailed(
                        VotingFlowError.missingActiveSession.localizedDescription
                    ))
                }

                let roundId = activeSession.voteRoundId.hexString
                let cachedNotes = state.walletNotes
                let network = zcashSDKEnvironment.network
                let walletDbPath = databaseFiles.dataDbURLFor(network).path
                let networkId: UInt32 = network.networkType == .mainnet ? 0 : 1
                let accountIndex: UInt32 = state.selectedWalletAccount.flatMap(\.zip32AccountIndex).map { UInt32($0.index) } ?? 0
                guard let pirServerUrl = state.serviceConfig?.pirEndpoints.first?.url else {
                    logger.error("serviceConfig unexpectedly nil during delegation proof; aborting")
                    return .none
                }
                let storedSignatures = state.keystoneBundleSignatures
                let signedCount = storedSignatures.count

                return .run { [backgroundTask, votingCrypto, votingAPI, mnemonic, walletStorage] send in
                    let bgTaskId = await backgroundTask.beginTask("Keystone delegation proof")
                    do {
                        let senderPhrase = try walletStorage.exportWallet().seedPhrase.value()
                        let senderSeed = try mnemonic.toSeed(senderPhrase)
                        let hotkeyPhrase = try walletStorage.exportVotingHotkey().seedPhrase.value()
                        let hotkeySeed = try mnemonic.toSeed(hotkeyPhrase)
                        let noteChunks = cachedNotes.smartBundles().bundles
                        var completedBundles = Set<UInt32>()
                        for idx: UInt32 in 0..<UInt32(signedCount) {
                            if let _ = try? await votingCrypto.getDelegationTxHash(roundId, idx) {
                                completedBundles.insert(idx)
                            }
                        }

                        for (bundleIndex, sig) in storedSignatures.enumerated() {
                            let bundleIdx = UInt32(bundleIndex)
                            if completedBundles.contains(bundleIdx) {
                                logger.debug("Keystone delegation bundle \(bundleIdx) already submitted, skipping")
                                let overallProgress = Double(bundleIndex + 1) / Double(signedCount)
                                await send(.delegationProofProgress(overallProgress))
                                continue
                            }
                            let bundleNotes = noteChunks[bundleIndex]
                            logger.info("Keystone batch: proving bundle \(bundleIndex + 1)/\(signedCount)")

                            for try await event in votingCrypto.buildAndProveDelegation(
                                roundId,
                                bundleIdx,
                                bundleNotes,
                                senderSeed,
                                hotkeySeed,
                                networkId,
                                accountIndex,
                                pirServerUrl
                            ) {
                                switch event {
                                case .progress(let progress):
                                    let overallProgress = (Double(bundleIndex) + progress) / Double(signedCount)
                                    logger.debug("ZKP #1 bundle \(bundleIdx) progress: \(Int(progress * 100))%")
                                    await send(.delegationProofProgress(overallProgress))
                                case .completed(let proof):
                                    logger.info("ZKP #1 bundle \(bundleIdx) COMPLETE — proof size: \(proof.count) bytes")
                                }
                            }

                            // Submit delegation TX using the stored Keystone signature
                            let registration = try await votingCrypto.getDelegationSubmissionWithKeystoneSig(
                                roundId, bundleIdx, sig.sig, sig.sighash
                            )
                            if registration.rk != sig.rk ||
                                registration.spendAuthSig != sig.sig ||
                                registration.sighash != sig.sighash {
                                throw VotingFlowError.invalidDelegationSignature
                            }
                            logger.debug(
                                """
                                Keystone delegation tuple \
                                rk=\(Data(registration.rk.prefix(8)).hexString) \
                                sighash=\(Data(sig.sighash.prefix(8)).hexString) \
                                sig=\(Data(sig.sig.prefix(8)).hexString)
                                """
                            )
                            let delegTxResult = try await votingAPI.submitDelegation(registration)
                            logger.info("Delegation TX \(bundleIdx) submitted: \(delegTxResult.txHash)")

                            // Persist TX hash for crash recovery
                            try await votingCrypto.storeDelegationTxHash(roundId, bundleIdx, delegTxResult.txHash)

                            let delegDeadline = Date().addingTimeInterval(90)
                            var delegConfirmation: TxConfirmation?
                            repeat {
                                delegConfirmation = try? await votingAPI.fetchTxConfirmation(delegTxResult.txHash)
                                if delegConfirmation != nil { break }
                                try await Task.sleep(for: .seconds(2))
                            } while Date() < delegDeadline

                            guard let delegConfirmation, delegConfirmation.code == 0,
                                  let leafValue = delegConfirmation.event(ofType: "delegate_vote")?.attribute(forKey: "leaf_index"),
                                  let vanPosition = UInt32(leafValue)
                            else {
                                throw VotingFlowError.delegationTxFailed(
                                    code: delegConfirmation?.code ?? 0
                                )
                            }
                            try await votingCrypto.storeVanPosition(roundId, bundleIdx, vanPosition)
                            logger.debug("VAN position stored for bundle \(bundleIdx): \(vanPosition)")
                        }

                        await send(.delegationProofCompleted)
                    } catch {
                        await backgroundTask.endTask(bgTaskId)
                        throw error
                    }
                    await backgroundTask.endTask(bgTaskId)
                } catch: { error, send in
                    await send(.delegationProofFailed(error.localizedDescription))
                }

            case .keystoneSignaturesRestored(let savedSigs):
                // Restore in-memory signatures from persisted recovery state
                state.keystoneBundleSignatures = savedSigs.map {
                    State.KeystoneBundleSignature(sig: $0.sig, sighash: $0.sighash, rk: $0.rk)
                }
                state.currentKeystoneBundleIndex = UInt32(savedSigs.count)
                if UInt32(savedSigs.count) >= state.bundleCount {
                    // All bundles were signed — go straight to batch proving
                    state.keystoneSigningStatus = .idle
                    state.screenStack = [.pollsList, .proposalList]
                    state.delegationProofStatus = .generating(progress: 0)
                    return .send(.keystoneAllBundlesSigned)
                } else {
                    // Some bundles signed — show signing screen and auto-start next PCZT build
                    state.keystoneSigningStatus = .idle
                    state.screenStack = [.delegationSigning]
                    return .send(.delegationApproved)
                }

            case .keystoneShowSigningScreen:
                state.screenStack = [.delegationSigning]
                return .send(.delegationApproved)

            case .skipRemainingKeystoneBundles:
                // Show confirmation alert with locked-in / giving-up amounts.
                let signedCount = state.keystoneBundleSignatures.count
                guard signedCount > 0 else { return .none }
                state.skipBundlesAlert = .confirmSkip(
                    lockedIn: state.signedBundlesZECString,
                    givingUp: state.skippedBundlesZECString
                )
                return .none

            case .skipBundlesAlert(.presented(.skipRemainingKeystoneBundlesConfirmed)):
                state.skipBundlesAlert = nil
                return .send(.skipRemainingKeystoneBundlesConfirmed)

            case .skipBundlesAlert(.dismiss):
                state.skipBundlesAlert = nil
                return .none

            case .skipBundlesAlert:
                return .none

            case .skipRemainingKeystoneBundlesConfirmed:
                // User confirmed skip — proceed with only the signed bundles.
                let signedCount = UInt32(state.keystoneBundleSignatures.count)
                guard signedCount > 0 else { return .none }
                state.bundleCount = signedCount

                // Recalculate votingWeight to reflect only signed bundles' quantized weight
                let bundles = state.walletNotes.smartBundles().bundles
                let signedWeight = state.keystoneBundleSignatures.indices.reduce(UInt64(0)) { total, i in
                    guard i < bundles.count else { return total }
                    let raw = bundles[i].reduce(UInt64(0)) { $0 + $1.value }
                    return total + quantizeWeight(raw)
                }
                state.votingWeight = signedWeight

                state.pendingGovernancePczt = nil
                state.pendingUnsignedDelegationPczt = nil
                state.keystoneSigningStatus = .idle
                state.screenStack = [.pollsList, .proposalList]
                state.delegationProofStatus = .generating(progress: 0)

                // Delete skipped bundles from DB so proof_generated reflects reality
                let roundId = state.roundId
                return .run { [votingCrypto] send in
                    try await votingCrypto.deleteSkippedBundles(roundId, signedCount)
                    await send(.keystoneAllBundlesSigned)
                } catch: { error, send in
                    await send(.delegationProofFailed(error.localizedDescription))
                }

            case .keystoneBundleAdvance:
                // Legacy — no longer used; signing loop is handled by keystoneBundleSignatureStored.
                return .none

            case .spendAuthSignatureExtractionFailed(let error):
                state.keystoneSigningStatus = .failed(VotingErrorMapper.userFriendlyMessage(from: error))
                return .none

            case .delegationProofProgress(let progress):
                state.delegationProofStatus = .generating(progress: progress)
                return .none

            case .delegationProofCompleted:
                state.delegationProofStatus = .complete
                state.isDelegationProofInFlight = false
                state.currentKeystoneBundleIndex = 0
                state.keystoneBundleSignatures = []

                // Pop the delegation signing screen if it was pushed for deferred delegation.
                if state.screenStack.last == .delegationSigning {
                    state.screenStack.removeLast()
                }

                let roundId = state.roundId
                // Auto-resume batch submission immediately so the UI transitions
                // to .submitting without a visible gap. Run cleanup in parallel.
                if state.pendingBatchSubmission {
                    state.pendingBatchSubmission = false
                    // Reset so canSubmitBatch passes — .authorizing makes
                    // isBatchSubmitting true which blocks the guard.
                    state.batchSubmissionStatus = .idle
                    return .merge(
                        .send(.authenticationSucceeded),
                        .run { [votingCrypto] _ in
                            await votingCrypto.refreshState(roundId)
                            try await votingCrypto.clearRecoveryState(roundId)
                        }
                    )
                }
                return .run { [votingCrypto] _ in
                    await votingCrypto.refreshState(roundId)
                    try await votingCrypto.clearRecoveryState(roundId)
                }

            case .delegationProofFailed(let error):
                state.currentKeystoneBundleIndex = 0
                state.keystoneBundleSignatures = []
                let userMessage: String
                if error.contains("total_weight must yield at least 1 ballot") {
                    let weightStr = Zatoshi(Int64(state.votingWeight)).decimalString()
                    let requiredStr = Zatoshi(Int64(ballotDivisor)).decimalString()
                    userMessage = """
                        Your shielded balance at the snapshot (\(weightStr) ZEC) \
                        is below the minimum required to vote (\(requiredStr) ZEC).
                        """
                } else {
                    userMessage = VotingErrorMapper.userFriendlyMessage(from: error)
                }
                state.delegationProofStatus = .failed(userMessage)
                state.isDelegationProofInFlight = false
                return .none

            // MARK: - Proposal List

            case .proposalTapped(let id):
                state.selectedProposalId = id
                state.screenStack.append(.proposalDetail(id: id))
                return .none

            // MARK: - Proposal Detail

            case let .castVote(proposalId, choice):
                guard state.votes[proposalId] == nil else { return .none }
                if state.draftVotes[proposalId] == choice {
                    state.draftVotes.removeValue(forKey: proposalId)
                } else {
                    state.draftVotes[proposalId] = choice
                }
                Self.persistDrafts(state.draftVotes, walletId: state.walletId, roundId: state.roundId)
                return .none

            case .voteSubmissionBundleStarted(let index):
                state.currentVoteBundleIndex = index
                state.voteSubmissionStep = .preparingProof
                return .none

            case .voteSubmissionStepUpdated(let step):
                state.voteSubmissionStep = step
                return .none

            case .advanceAfterVote:
                state.isSubmittingVote = false
                state.submittingProposalId = nil
                state.voteSubmissionStep = nil
                state.currentVoteBundleIndex = nil
                // Return to proposal list so the user can pick their next vote freely.
                if case .proposalDetail = state.currentScreen {
                    state.screenStack.removeLast()
                }
                // Auto-resume: if there are remaining drafts after a crash-recovered
                // vote, continue submitting.
                if state.canSubmitBatch {
                    let remainingCount = state.draftVotes.count
                    logger.info("Auto-resuming batch submission with \(remainingCount) remaining drafts")
                    return .send(.submitAllDrafts)
                }
                // Vote finished — start share tracking now that delegation rows are written.
                if !state.votes.isEmpty && state.shareTrackingStatus == .idle {
                    state.shareTrackingStatus = .loading
                    return .send(.loadShareDelegations)
                }
                return .none

            case .backToList:
                if case .proposalDetail = state.currentScreen {
                    state.screenStack.removeLast()
                } else if case .confirmSubmission = state.currentScreen {
                    state.screenStack.removeLast()
                } else if case .reviewVotes = state.currentScreen {
                    state.screenStack.removeLast()
                } else if case .proposalList = state.currentScreen, state.screenStack.count > 1 {
                    state.screenStack.removeLast()
                }
                return .none

            case .nextProposalDetail:
                guard let index = state.detailProposalIndex else { return .none }
                let isLast = index == state.votingRound.proposals.count - 1

                if isLast {
                    if state.allDrafted {
                        // All answered → review
                        state.screenStack.removeLast()
                        state.screenStack.append(.reviewVotes)
                    }
                    // If unanswered → .none; view handles sheet display
                } else {
                    let nextId = state.votingRound.proposals[index + 1].id
                    state.selectedProposalId = nextId
                    state.screenStack.removeLast()
                    state.screenStack.append(.proposalDetail(id: nextId))
                }
                return .none

            case .navigateToReview:
                state.screenStack.append(.reviewVotes)
                return .none

            case .navigateToConfirmation:
                state.screenStack.append(.confirmSubmission)
                return .none

            case .confirmUnanswered:
                // Auto-draft Abstain for every unanswered proposal, then go to review.
                for proposal in state.votingRound.proposals where state.draftVotes[proposal.id] == nil {
                    let abstainIndex: UInt32
                    if let existing = proposal.options.first(where: {
                        $0.label.localizedCaseInsensitiveContains("abstain")
                    }) {
                        abstainIndex = existing.index
                    } else {
                        abstainIndex = (proposal.options.map(\.index).max() ?? 0) + 1
                    }
                    state.draftVotes[proposal.id] = .option(abstainIndex)
                }
                Self.persistDrafts(state.draftVotes, walletId: state.walletId, roundId: state.roundId)
                state.screenStack.removeLast()
                state.screenStack.append(.reviewVotes)
                return .none

            case .dismissUnanswered:
                if case .proposalDetail = state.currentScreen {
                    state.screenStack.removeLast()
                }
                return .none

            case .previousProposalDetail:
                if let index = state.detailProposalIndex, index > 0 {
                    let prevId = state.votingRound.proposals[index - 1].id
                    state.selectedProposalId = prevId
                    state.screenStack.removeLast()
                    state.screenStack.append(.proposalDetail(id: prevId))
                }
                return .none

            // MARK: - Batch Voting

            case let .setDraftVote(proposalId, choice):
                guard state.votes[proposalId] == nil else { return .none }
                state.draftVotes[proposalId] = choice
                Self.persistDrafts(state.draftVotes, walletId: state.walletId, roundId: state.roundId)
                // Pop back to the list so the user can continue drafting other proposals
                if case .proposalDetail = state.currentScreen {
                    state.screenStack.removeLast()
                }
                return .none

            case let .clearDraftVote(proposalId):
                state.draftVotes.removeValue(forKey: proposalId)
                Self.persistDrafts(state.draftVotes, walletId: state.walletId, roundId: state.roundId)
                return .none

            case .submitAllDrafts:
                guard state.canSubmitBatch else { return .none }
                guard state.activeSession != nil else { return .none }

                // Non-Keystone: require device authentication (FaceID/TouchID/Passcode)
                // before proceeding. Keystone users authenticate via their hardware device.
                // Skip auth when resuming after delegation (pendingBatchSubmission flow).
                if !state.isKeystoneUser && !state.pendingBatchSubmission {
                    return .run { [localAuthentication] send in
                        guard await localAuthentication.authenticate() else { return }
                        await send(.authenticationSucceeded)
                    }
                }
                return .send(.authenticationSucceeded)

            case .authenticationSucceeded:
                guard state.canSubmitBatch || state.isBatchSubmitting else { return .none }
                guard state.activeSession != nil else { return .none }

                // Record the moment the user confirmed their vote. Persisted so the
                // Results screen can show "Voted MMM d · Voting Power X.XXX ZEC"
                // and the polls list can show "X of Y voted" long after the
                // active session is gone. Recorded once per round —
                // re-confirmations (e.g. retry after a partial failure) keep the
                // original timestamp.
                if state.voteRecord == nil {
                    let record = VoteRecord(
                        votedAt: Date(),
                        votingWeight: state.votingWeight,
                        proposalCount: state.draftVotes.count
                    )
                    state.voteRecord = record
                    Self.persistVoteRecord(record, walletId: state.walletId, roundId: state.roundId)
                    state.voteRecords[state.roundId] = record
                }

                // Keystone: delegation requires QR signing UI, so route through
                // the delegation signing screen before batch submission.
                if state.isKeystoneUser && !state.isDelegationReady {
                    state.pendingBatchSubmission = true
                    state.screenStack.append(.delegationSigning)
                    return .send(.startDelegationProof)
                }

                let drafts = state.draftVotes.sorted { $0.key < $1.key }
                let totalCount = drafts.count
                let delegationDone = state.isDelegationReady
                state.batchSubmissionStatus = delegationDone
                    ? .submitting(currentIndex: 0, totalCount: totalCount, currentProposalId: drafts[0].key)
                    : .authorizing
                state.batchVoteErrors = [:]

                let roundId = state.roundId
                let network = zcashSDKEnvironment.network
                let networkId: UInt32 = network.networkType == .mainnet ? 0 : 1
                guard
                    let chainNodeUrl = state.serviceConfig?.voteServers.first?.url,
                    let pirServerUrl = state.serviceConfig?.pirEndpoints.first?.url
                else {
                    logger.error("serviceConfig unexpectedly nil during vote submission; aborting")
                    return .none
                }
                let bundleCount = state.bundleCount
                let singleShare = state.activeSession?.isLastMoment ?? false
                let proposals = state.votingRound.proposals
                let cachedNotes = state.walletNotes
                let roundName = state.votingRound.title

                let submitAtDeadline: Double?
                if singleShare {
                    submitAtDeadline = nil
                } else if let session = state.activeSession, let buffer = session.lastMomentBuffer {
                    submitAtDeadline = session.voteEndTime.timeIntervalSince1970 - buffer
                } else {
                    submitAtDeadline = nil
                }

                return .run { [backgroundTask, votingAPI, votingCrypto, mnemonic, walletStorage] send in
                    let bgTaskId = await backgroundTask.beginTask("Batch vote submission")
                    let _ = await backgroundTask.beginContinuedProcessing(
                        "co.zodl.voting.*",
                        "Submitting votes",
                        "Sending \(totalCount) vote\(totalCount == 1 ? "" : "s") to the network"
                    )
                    defer {
                        Task {
                            await backgroundTask.endContinuedProcessing()
                            await backgroundTask.endTask(bgTaskId)
                        }
                    }

                    let hotkeyPhrase = try walletStorage.exportVotingHotkey().seedPhrase.value()
                    let hotkeySeed = try mnemonic.toSeed(hotkeyPhrase)

                    // --- Delegation (ZKP #1) — run inline if not already done ---
                    if !delegationDone {
                        let senderPhrase = try walletStorage.exportWallet().seedPhrase.value()
                        let senderSeed = try mnemonic.toSeed(senderPhrase)
                        try await Self.runDelegationPipeline(
                            roundId: roundId,
                            cachedNotes: cachedNotes,
                            senderSeed: senderSeed,
                            hotkeySeed: hotkeySeed,
                            networkId: networkId,
                            accountIndex: 0,
                            roundName: roundName,
                            pirServerUrl: pirServerUrl,
                            votingCrypto: votingCrypto,
                            votingAPI: votingAPI,
                            send: send
                        )
                    }

                    // Transition from .authorizing to .submitting now that delegation is done.
                    await send(.batchSubmissionProgress(
                        currentIndex: 0, totalCount: totalCount, proposalId: drafts[0].key
                    ))

                    var successCount = 0
                    var failCount = 0

                    for (draftIndex, draft) in drafts.enumerated() {
                        let proposalId = draft.key
                        let choice = draft.value
                        let numOptions = UInt32(proposals.first { $0.id == proposalId }?.options.count ?? 3)

                        await send(.batchSubmissionProgress(currentIndex: draftIndex, totalCount: totalCount, proposalId: proposalId))

                        do {
                            let existingVotes = try await votingCrypto.getVotes(roundId)
                            let submittedBundles = Set(
                                existingVotes
                                    .filter { $0.proposalId == proposalId && $0.submitted }
                                    .map(\.bundleIndex)
                            )

                            for bundleIndex: UInt32 in 0..<bundleCount {
                                if submittedBundles.contains(bundleIndex) {
                                    logger.debug("Batch: bundle \(bundleIndex + 1)/\(bundleCount) already submitted for proposal \(proposalId)")
                                    continue
                                }

                                await send(.voteSubmissionBundleStarted(bundleIndex))
                                await send(.voteSubmissionStepUpdated(.preparingProof))

                                // Crash recovery: check if TX landed on-chain but wasn't marked
                                if let cachedTxHash = try? await votingCrypto.getVoteTxHash(roundId, bundleIndex, proposalId) {
                                    if let confirmation = try? await votingAPI.fetchTxConfirmation(cachedTxHash),
                                       confirmation.code == 0,
                                       let leafPair = confirmation.event(ofType: "cast_vote")?.attribute(forKey: "leaf_index") {
                                        let leafParts = leafPair.split(separator: ",")
                                        if leafParts.count == 2,
                                           let vanIdx = UInt32(leafParts[0]),
                                           let vcIdx = UInt64(leafParts[1]) {
                                            try await votingCrypto.storeVanPosition(roundId, bundleIndex, vanIdx)
                                            if let savedBundle = try? await votingCrypto.getVoteCommitmentBundle(roundId, bundleIndex, proposalId) {
                                                await send(.voteSubmissionStepUpdated(.sendingShares))
                                                var payloads = try await votingCrypto.buildSharePayloads(
                                                    savedBundle.encShares, savedBundle, choice, numOptions, vcIdx, singleShare
                                                )
                                                let now = Date().timeIntervalSince1970
                                                for i in payloads.indices {
                                                    if let deadline = submitAtDeadline, deadline > now {
                                                        payloads[i].submitAt = UInt64(now + Double.random(in: 0..<(deadline - now)))
                                                    } else {
                                                        payloads[i].submitAt = 0
                                                    }
                                                }
                                                let recoveryInfos = try await Self.delegateSharesWithRetry(payloads, roundId: roundId, votingAPI: votingAPI)
                                                for info in recoveryInfos {
                                                    guard let payload = payloads.first(where: {
                                                        $0.encShare.shareIndex == info.shareIndex && $0.proposalId == info.proposalId
                                                    }) else { continue }
                                                    let blindIdx = Int(info.shareIndex)
                                                    guard blindIdx < savedBundle.shareBlindFactors.count else { continue }
                                                    do {
                                                        let nfHex = try votingCrypto.computeShareNullifier(
                                                            [UInt8](savedBundle.voteCommitment),
                                                            info.shareIndex,
                                                            [UInt8](savedBundle.shareBlindFactors[blindIdx])
                                                        )
                                                        try await votingCrypto.recordShareDelegation(
                                                            roundId, bundleIndex, info.proposalId,
                                                            info.shareIndex, info.acceptedByServers,
                                                            [UInt8](dataFromHex(nfHex)), payload.submitAt
                                                        )
                                                    } catch {
                                                        logger.warning("Batch recovery: failed to record share delegation for share \(info.shareIndex): \(error)")
                                                    }
                                                }
                                            }
                                            try await votingCrypto.markVoteSubmitted(roundId, bundleIndex, proposalId)
                                            continue
                                        }
                                    }
                                }

                                let anchorHeight = try await votingCrypto.syncVoteTree(roundId, chainNodeUrl)
                                let vanWitness = try await votingCrypto.generateVanWitness(roundId, bundleIndex, anchorHeight)

                                var builtBundle: VoteCommitmentBundle?
                                for try await event in votingCrypto.buildVoteCommitment(
                                    roundId, bundleIndex, hotkeySeed, networkId, proposalId, choice,
                                    numOptions, vanWitness.authPath, vanWitness.position, vanWitness.anchorHeight, singleShare
                                ) {
                                    if case .completed(let bundle) = event {
                                        builtBundle = bundle
                                    }
                                }
                                guard let builtBundle else {
                                    throw VotingFlowError.missingVoteCommitmentBundle
                                }

                                try await votingCrypto.storeVoteCommitmentBundle(roundId, bundleIndex, proposalId, builtBundle, 0)

                                let castVoteSig = try await votingCrypto.signCastVote(hotkeySeed, networkId, builtBundle)

                                await send(.voteSubmissionStepUpdated(.confirming))
                                let txResult = try await votingAPI.submitVoteCommitment(builtBundle, castVoteSig)
                                try await votingCrypto.storeVoteTxHash(roundId, bundleIndex, proposalId, txResult.txHash)

                                let voteDeadline = Date().addingTimeInterval(90)
                                var voteConfirmation: TxConfirmation?
                                repeat {
                                    voteConfirmation = try? await votingAPI.fetchTxConfirmation(txResult.txHash)
                                    if voteConfirmation != nil { break }
                                    try await Task.sleep(for: .seconds(2))
                                } while Date() < voteDeadline

                                guard let voteConfirmation, voteConfirmation.code == 0,
                                      let leafPair = voteConfirmation.event(ofType: "cast_vote")?.attribute(forKey: "leaf_index")
                                else {
                                    throw VotingFlowError.voteCommitmentTxFailed(code: voteConfirmation?.code ?? 0)
                                }
                                let leafParts = leafPair.split(separator: ",")
                                guard leafParts.count == 2,
                                      let vanIdx = UInt32(leafParts[0]),
                                      let vcIdx = UInt64(leafParts[1])
                                else {
                                    throw VotingFlowError.voteCommitmentTxFailed(code: 0)
                                }

                                try await votingCrypto.storeVanPosition(roundId, bundleIndex, vanIdx)

                                await send(.voteSubmissionStepUpdated(.sendingShares))
                                var payloads = try await votingCrypto.buildSharePayloads(
                                    builtBundle.encShares, builtBundle, choice, numOptions, vcIdx, singleShare
                                )
                                let nowSec = Date().timeIntervalSince1970
                                for i in payloads.indices {
                                    if let deadline = submitAtDeadline, deadline > nowSec {
                                        payloads[i].submitAt = UInt64(nowSec + Double.random(in: 0..<(deadline - nowSec)))
                                    } else {
                                        payloads[i].submitAt = 0
                                    }
                                }
                                try await votingCrypto.storeVoteCommitmentBundle(roundId, bundleIndex, proposalId, builtBundle, vcIdx)
                                let batchDelegatedInfos = try await Self.delegateSharesWithRetry(payloads, roundId: roundId, votingAPI: votingAPI)
                                for info in batchDelegatedInfos {
                                    guard let payload = payloads.first(where: {
                                        $0.encShare.shareIndex == info.shareIndex && $0.proposalId == info.proposalId
                                    }) else { continue }
                                    let blindIndex = Int(info.shareIndex)
                                    guard blindIndex < builtBundle.shareBlindFactors.count else { continue }
                                    do {
                                        let nullifierHex = try votingCrypto.computeShareNullifier(
                                            [UInt8](builtBundle.voteCommitment),
                                            info.shareIndex,
                                            [UInt8](builtBundle.shareBlindFactors[blindIndex])
                                        )
                                        try await votingCrypto.recordShareDelegation(
                                            roundId, bundleIndex, info.proposalId,
                                            info.shareIndex, info.acceptedByServers,
                                            [UInt8](dataFromHex(nullifierHex)), payload.submitAt
                                        )
                                    } catch {
                                        logger.warning("Batch: failed to record share delegation for share \(info.shareIndex): \(error)")
                                    }
                                }
                                try await votingCrypto.markVoteSubmitted(roundId, bundleIndex, proposalId)
                            }

                            successCount += 1
                            await send(.batchVoteSubmitted(proposalId: proposalId, choice: choice))
                        } catch {
                            failCount += 1
                            logger.error("Batch vote failed for proposal \(proposalId): \(error)")
                            await send(.batchVoteFailed(
                                proposalId: proposalId,
                                error: VotingErrorMapper.userFriendlyMessage(from: error.localizedDescription)
                            ))
                        }
                    }

                    await send(.batchSubmissionCompleted(successCount: successCount, failCount: failCount))
                } catch: { error, send in
                    logger.error("Batch submission failed at top level: \(error)")
                    await send(.batchSubmissionFailed(
                        error: VotingErrorMapper.userFriendlyMessage(from: error.localizedDescription),
                        submittedCount: 0,
                        totalCount: totalCount
                    ))
                }

            case let .batchSubmissionProgress(currentIndex, totalCount, proposalId):
                state.batchSubmissionStatus = .submitting(
                    currentIndex: currentIndex,
                    totalCount: totalCount,
                    currentProposalId: proposalId
                )
                state.submittingProposalId = proposalId
                state.isSubmittingVote = true
                return .none

            case let .batchVoteSubmitted(proposalId, choice):
                state.votes[proposalId] = choice
                state.draftVotes.removeValue(forKey: proposalId)
                Self.persistDrafts(state.draftVotes, walletId: state.walletId, roundId: state.roundId)
                return .none

            case let .batchVoteFailed(proposalId, error):
                state.batchVoteErrors[proposalId] = error
                return .none

            case let .batchSubmissionCompleted(successCount, failCount):
                state.isSubmittingVote = false
                state.submittingProposalId = nil
                state.voteSubmissionStep = nil
                state.currentVoteBundleIndex = nil
                state.batchSubmissionStatus = .completed(successCount: successCount, failCount: failCount)
                // Clean up persisted drafts when all votes succeeded
                if failCount == 0 {
                    Self.clearPersistedDrafts(walletId: state.walletId, roundId: state.roundId)
                }
                return .none

            case let .batchSubmissionFailed(error, submittedCount, totalCount):
                state.isSubmittingVote = false
                state.submittingProposalId = nil
                state.voteSubmissionStep = nil
                state.currentVoteBundleIndex = nil
                state.batchSubmissionStatus = .failed(
                    lastError: error,
                    submittedCount: submittedCount,
                    totalCount: totalCount
                )
                return .none

            case .dismissBatchResults:
                state.batchSubmissionStatus = .idle
                state.batchVoteErrors = [:]
                return .none

            // MARK: - Complete

            case .doneTapped:
                state.screenStack = [.pollsList, .proposalList]
                return .none
            }
        }
        .ifLet(\.$keystoneScan, action: \.keystoneScan) {
            Scan()
        }
    }

    private func sessionBackedRound(from session: VotingSession, title: String, fallback: VotingRound) -> VotingRound {
        let proposals = session.proposals.isEmpty ? fallback.proposals : session.proposals
        // Prefer the on-chain title, then the caller-provided title, then the fallback
        let resolvedTitle = !session.title.isEmpty ? session.title : (!title.isEmpty ? title : fallback.title)
        return VotingRound(
            id: session.voteRoundId.hexString,
            title: resolvedTitle,
            description: session.description.isEmpty ? fallback.description : session.description,
            discussionURL: session.discussionURL ?? fallback.discussionURL,
            snapshotHeight: session.snapshotHeight,
            snapshotDate: fallback.snapshotDate,
            votingStart: fallback.votingStart,
            votingEnd: session.voteEndTime,
            proposals: proposals
        )
    }

    private func reconcileProposalState(_ state: inout State) {
        let validProposalIDs = Set(state.votingRound.proposals.map(\.id))
        state.votes = state.votes.filter { validProposalIDs.contains($0.key) }

        if let selectedProposalId = state.selectedProposalId,
            !validProposalIDs.contains(selectedProposalId) {
            state.selectedProposalId = nil
        }

        if case .proposalDetail(let proposalId) = state.currentScreen,
            !validProposalIDs.contains(proposalId) {
            if !state.screenStack.isEmpty {
                state.screenStack.removeLast()
            }
            state.screenStack.append(.proposalList)
        }
    }

    /// Run the non-Keystone delegation pipeline (ZKP #1) for all bundles.
    /// Called inline from submitAllDrafts before the vote pipeline.
    private static func runDelegationPipeline(
        roundId: String,
        cachedNotes: [NoteInfo],
        senderSeed: [UInt8],
        hotkeySeed: [UInt8],
        networkId: UInt32,
        accountIndex: UInt32,
        roundName: String,
        pirServerUrl: String,
        votingCrypto: VotingCryptoClient,
        votingAPI: VotingAPIClient,
        send: Send<Action>
    ) async throws {
        let noteChunks = cachedNotes.smartBundles().bundles
        let bundleCount = UInt32(noteChunks.count)
        var completedBundles = Set<UInt32>()
        for idx: UInt32 in 0..<bundleCount {
            if let _ = try? await votingCrypto.getDelegationTxHash(roundId, idx) {
                completedBundles.insert(idx)
            }
        }

        for bundleIndex: UInt32 in 0..<bundleCount {
            if completedBundles.contains(bundleIndex) {
                logger.debug("Delegation bundle \(bundleIndex + 1)/\(bundleCount) already submitted, skipping")
                continue
            }
            let bundleNotes = noteChunks[Int(bundleIndex)]
            logger.info("Delegation bundle \(bundleIndex + 1)/\(bundleCount) (\(bundleNotes.count) notes)")

            _ = try await votingCrypto.buildGovernancePczt(
                roundId, bundleIndex, bundleNotes,
                senderSeed, hotkeySeed, networkId, accountIndex, roundName,
                nil, nil
            )

            for try await event in votingCrypto.buildAndProveDelegation(
                roundId, bundleIndex, bundleNotes,
                senderSeed, hotkeySeed, networkId, accountIndex, pirServerUrl
            ) {
                switch event {
                case .progress(let progress):
                    let overallProgress = (Double(bundleIndex) + progress) / Double(bundleCount)
                    logger.debug("ZKP #1 bundle \(bundleIndex) progress: \(Int(progress * 100))%")
                    await send(.delegationProofProgress(overallProgress))
                case .completed(let proof):
                    logger.info("ZKP #1 bundle \(bundleIndex) COMPLETE — proof size: \(proof.count) bytes")
                }
            }

            let registration = try await votingCrypto.getDelegationSubmission(
                roundId, bundleIndex, senderSeed, networkId, accountIndex
            )
            let delegTxResult = try await votingAPI.submitDelegation(registration)
            logger.info("Delegation TX \(bundleIndex) submitted: \(delegTxResult.txHash)")

            try await votingCrypto.storeDelegationTxHash(roundId, bundleIndex, delegTxResult.txHash)

            let delegDeadline = Date().addingTimeInterval(90)
            var delegConfirmation: TxConfirmation?
            repeat {
                delegConfirmation = try? await votingAPI.fetchTxConfirmation(delegTxResult.txHash)
                if delegConfirmation != nil { break }
                try await Task.sleep(for: .seconds(2))
            } while Date() < delegDeadline

            guard let delegConfirmation, delegConfirmation.code == 0,
                  let leafValue = delegConfirmation.event(ofType: "delegate_vote")?.attribute(forKey: "leaf_index"),
                  let vanPosition = UInt32(leafValue)
            else {
                throw VotingFlowError.delegationTxFailed(
                    code: delegConfirmation?.code ?? 0
                )
            }
            try await votingCrypto.storeVanPosition(roundId, bundleIndex, vanPosition)
            logger.debug("VAN position stored for bundle \(bundleIndex): \(vanPosition)")
        }

        await send(.delegationProofCompleted)
    }

    /// Retry share delegation up to 3 times with 2-second backoff.
    @discardableResult
    private static func delegateSharesWithRetry(
        _ payloads: [SharePayload],
        roundId: String,
        votingAPI: VotingAPIClient
    ) async throws -> [DelegatedShareInfo] {
        var lastShareError: Error?
        for attempt in 1...3 {
            do {
                return try await votingAPI.delegateShares(payloads, roundId)
            } catch {
                lastShareError = error
                logger.warning("delegateShares attempt \(attempt)/3 failed: \(error)")
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }
        throw lastShareError!
    }

    // MARK: - Draft Persistence

    private static let draftPrefix = "voting.draftVotes."
    private static let voteRecordPrefix = "voting.voteRecord."

    /// Persisted record of when the user confirmed their vote in a given round,
    /// the voting weight at that moment, and how many proposals they voted on.
    /// Survives app termination so the Results screen can render
    /// "Voted Feb 15 · Voting Power X.XXX ZEC" and the polls list can show the
    /// "X of Y voted" indicator days after submission, even though the live
    /// session state is per-session.
    public struct VoteRecord: Equatable {
        public let votedAt: Date
        public let votingWeight: UInt64
        public let proposalCount: Int

        public init(votedAt: Date, votingWeight: UInt64, proposalCount: Int) {
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

    private static func draftKey(walletId: String, roundId: String) -> String {
        "\(draftPrefix)\(walletId)|\(roundId)"
    }

    /// Persist draft votes to UserDefaults so they survive app termination.
    static func persistDrafts(_ drafts: [UInt32: VoteChoice], walletId: String, roundId: String) {
        let key = draftKey(walletId: walletId, roundId: roundId)
        if drafts.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            let encoded = drafts.reduce(into: [String: UInt32]()) { dict, entry in
                dict[String(entry.key)] = entry.value.index
            }
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Load persisted draft votes for a round.
    static func loadDrafts(walletId: String, roundId: String) -> [UInt32: VoteChoice] {
        let key = draftKey(walletId: walletId, roundId: roundId)
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: UInt32] else {
            return [:]
        }
        return raw.reduce(into: [UInt32: VoteChoice]()) { dict, entry in
            if let proposalId = UInt32(entry.key) {
                dict[proposalId] = .option(entry.value)
            }
        }
    }

    /// Remove all persisted drafts for a round.
    static func clearPersistedDrafts(walletId: String, roundId: String) {
        UserDefaults.standard.removeObject(forKey: draftKey(walletId: walletId, roundId: roundId))
    }
}

// MARK: - Note Bundling

/// Result of value-aware note bundling on the Swift side.
private struct BundleResult {
    let bundles: [[NoteInfo]]
    let eligibleWeight: UInt64
    let droppedCount: Int
}

private extension Array where Element == NoteInfo {
    /// Value-aware bundling using greedy min-total assignment.
    ///
    /// Algorithm mirrors the Rust `chunk_notes` for client-side use:
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

/// Convert hex string to Data (used for share confirmation polling).
private func dataFromHex(_ hex: String) -> Data {
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
            TextState("Skip Remaining Bundles?")
        } actions: {
            ButtonState(role: .destructive, action: .skipRemainingKeystoneBundlesConfirmed) {
                TextState("Skip")
            }
            ButtonState(role: .cancel, action: .skipBundlesAlert(.dismiss)) {
                TextState("Cancel")
            }
        } message: {
            TextState("You will vote with \(lockedIn) ZEC from your signed bundles. The remaining \(givingUp) ZEC in unsigned bundles will not be included. This cannot be changed for this round.")
        }
    }
}
