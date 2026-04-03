import SwiftUI
import Combine
import ComposableArchitecture
import Generated
import UIComponents
import VotingModels

struct ProposalListView: View {
    @Environment(\.colorScheme)
    var colorScheme
    @State private var showSnapshotHeight = false
    @State private var now = Date()

    let store: StoreOf<Voting>

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeRemainingText: String {
        let end = store.votingRound.votingEnd
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return "Ended" }

        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else {
            return "\(minutes)m \(seconds)s"
        }
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                proposalScrollView()
            }
            .navigationTitle("Governance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.send(.dismissFlow)
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                if store.activeSession != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text(timeRemainingText)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(store.votingRound.votingEnd > now ? .green : .secondary)
                    }
                }
            }
            .onReceive(timer) { self.now = $0 }
            .onAppear { store.send(.governanceTabAppeared) }
            .onDisappear { store.send(.governanceTabDisappeared) }
            .sheet(isPresented: Binding(
                get: { store.showShareInfoSheet },
                set: { newValue in
                    if !newValue { store.send(.hideShareInfo) }
                }
            )) {
                ShareInfoSheet(
                    allConfirmed: {
                        guard let pid = store.shareInfoProposalId,
                              let p = store.shareDelegationProgressByProposal[pid] else { return store.allSharesConfirmed }
                        return p.confirmed >= p.total && p.total > 0
                    }(),
                    estimatedCompletion: store.shareInfoEstimatedCompletion,
                    roundDuration: store.activeSession.map {
                        $0.voteEndTime.timeIntervalSince($0.ceremonyStart)
                    } ?? 7200
                )
            }
        }
    }

    // MARK: - Scroll View

    @ViewBuilder
    private func proposalScrollView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if store.activeSession == nil {
                        noActiveRoundCard()
                    } else {
                        roundInfoCard()
                        progressHeader()

                        ForEach(store.votingRound.proposals) { proposal in
                            proposalCard(proposal)
                                .id(proposal.id)
                        }

                        batchFooter()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .onAppear {
                if let id = store.activeProposalId {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: store.activeProposalId) { newId in
                if let newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Round Info Header

    @ViewBuilder
    private func roundInfoCard() -> some View {
        VStack(spacing: 10) {
            Text(store.votingRound.title)
                .zFont(.semiBold, size: 15, style: Design.Text.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                detailPill(
                    label: "Snapshot",
                    value: store.votingRound.snapshotDate.formatted(date: .abbreviated, time: .omitted)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    showSnapshotHeight = true
                }
                .popover(isPresented: $showSnapshotHeight) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Block #\(store.votingRound.snapshotHeight.formatted())")
                        Text(store.votingRound.snapshotDate.formatted(date: .abbreviated, time: .standard))
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(12)
                    .compactPopover()
                }

                detailPill(
                    label: "Ends",
                    value: store.votingRound.votingEnd.formatted(date: .abbreviated, time: .omitted)
                )
                .frame(maxWidth: .infinity)

                detailPill(
                    label: "Eligible",
                    value: "\(store.votingWeightZECString) ZEC"
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private func detailPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Design.Text.primary.color(colorScheme))
        }
    }

    // MARK: - No Active Round

    @ViewBuilder
    private func noActiveRoundCard() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 28))
                .foregroundStyle(Design.Text.tertiary.color(colorScheme))

            Text("No Active Voting Round")
                .zFont(.semiBold, size: 18, style: Design.Text.primary)

            Text("There are no voting rounds in progress. Rounds are created by governance administrators — check back later.")
                .zFont(.regular, size: 13, style: Design.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
        .padding(.top, 8)
    }

    // MARK: - Status

    @ViewBuilder
    private func progressHeader() -> some View {
        if store.activeSession != nil {
            HStack {
                let draftCount = store.draftVotes.count
                if store.votedCount > 0 && draftCount > 0 {
                    Text("\(store.votedCount) submitted, \(draftCount) drafted")
                        .zFont(.medium, size: 14, style: Design.Text.secondary)
                } else if draftCount > 0 {
                    Text("\(draftCount) of \(store.totalProposals) drafted")
                        .zFont(.medium, size: 14, style: Design.Text.secondary)
                } else {
                    Text("\(store.votedCount) of \(store.totalProposals) voted")
                        .zFont(.medium, size: 14, style: Design.Text.secondary)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Card

extension ProposalListView {
    @ViewBuilder
    func proposalCard(_ proposal: Proposal) -> some View {
        let vote = store.votes[proposal.id]
        let draft = store.draftVotes[proposal.id]
        let displayChoice = vote ?? draft

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let zip = proposal.zipNumber {
                        ZIPBadge(zipNumber: zip)
                    }
                    Text(proposal.title)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)
                }

                Spacer(minLength: 8)

                if displayChoice != nil {
                    if store.submittingProposalId == proposal.id {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            VoteChip(
                                choice: displayChoice,
                                label: displayChoice.flatMap { c in proposal.options.first { $0.index == c.index }?.label },
                                color: displayChoice.map { voteOptionColor(for: $0.index, total: proposal.options.count) }
                            )
                        }
                    } else if vote != nil {
                        VoteChip(
                            choice: displayChoice,
                            label: displayChoice.flatMap { c in proposal.options.first { $0.index == c.index }?.label },
                            color: displayChoice.map { voteOptionColor(for: $0.index, total: proposal.options.count) }
                        )
                    } else {
                        // Draft chip — dashed outline style
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .semibold))
                            Text(displayChoice.flatMap { c in proposal.options.first { $0.index == c.index }?.label } ?? "Draft")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(displayChoice.map { voteOptionColor(for: $0.index, total: proposal.options.count) } ?? .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            Capsule()
                                .stroke(
                                    displayChoice.map { voteOptionColor(for: $0.index, total: proposal.options.count) }?.opacity(0.5) ?? .secondary,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 2])
                                )
                        )
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Text.tertiary.color(colorScheme))
            }

            Text(proposal.description)
                .zFont(.regular, size: 13, style: Design.Text.secondary)
                .lineLimit(2)

            // Share submission tracking (DB-backed)
            if vote != nil {
                if store.shareTrackingStatus == .loading {
                    ShareSubmissionStatus(
                        confirmed: 0, total: 1,
                        onInfoTapped: { store.send(.showShareInfo(proposal.id)) }
                    )
                } else if let progress = store.shareDelegationProgressByProposal[proposal.id], progress.total > 0 {
                    ShareSubmissionStatus(
                        confirmed: progress.confirmed, total: progress.total,
                        onInfoTapped: { store.send(.showShareInfo(proposal.id)) }
                    )
                }
            }
        }
        .padding(16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    displayChoice != nil
                        ? voteColor(displayChoice, proposal: proposal).opacity(vote != nil ? 0.3 : 0.15)
                        : Design.Surfaces.strokeSecondary.color(colorScheme),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            store.send(.proposalTapped(proposal.id))
        }
    }
}

// MARK: - Batch Footer

extension ProposalListView {
    @ViewBuilder
    func batchFooter() -> some View {
        let status = store.batchSubmissionStatus

        switch status {
        case .idle:
            if store.canSubmitBatch {
                let draftCount = store.draftVotes.count
                Button {
                    store.send(.reviewVoteSubmission)
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Submit \(draftCount) Vote\(draftCount == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)
            }

        case .authorizing:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authorizing vote...")
                            .zFont(.semiBold, size: 15, style: Design.Text.primary)
                        if case .generating(let progress) = store.delegationProofStatus {
                            Text("\(Int(progress * 100))%")
                                .zFont(.regular, size: 12, style: Design.Text.tertiary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(Design.Surfaces.bgPrimary.color(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 8)

        case let .submitting(currentIndex, totalCount, _):
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Submitting vote \(currentIndex + 1) of \(totalCount)...")
                            .zFont(.semiBold, size: 15, style: Design.Text.primary)
                        if let stepLabel = store.voteSubmissionStepLabel {
                            Text(stepLabel)
                                .zFont(.regular, size: 12, style: Design.Text.tertiary)
                        }
                    }
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: geo.size.width * Double(currentIndex + 1) / Double(totalCount))
                            .animation(.easeInOut(duration: 0.3), value: currentIndex)
                    }
                }
                .frame(height: 3)
            }
            .padding(16)
            .background(Design.Surfaces.bgPrimary.color(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 8)

        case let .completed(successCount, failCount):
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: failCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(failCount == 0 ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failCount == 0 ? "All votes submitted" : "Batch complete with errors")
                            .zFont(.semiBold, size: 15, style: Design.Text.primary)
                        Text("\(successCount) succeeded\(failCount > 0 ? ", \(failCount) failed" : "")")
                            .zFont(.regular, size: 13, style: Design.Text.secondary)
                    }
                    Spacer()
                }

                Button {
                    store.send(.dismissBatchResults)
                } label: {
                    Text("Done")
                        .zFont(.medium, size: 14, style: Design.Text.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Design.Surfaces.bgPrimary.color(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .background((failCount == 0 ? Color.green : Color.orange).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke((failCount == 0 ? Color.green : Color.orange).opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 8)

        case let .failed(lastError, submittedCount, totalCount):
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch submission failed")
                            .zFont(.semiBold, size: 15, style: Design.Text.primary)
                        Text("\(submittedCount) of \(totalCount) submitted. \(lastError)")
                            .zFont(.regular, size: 13, style: Design.Text.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                }

                Button {
                    store.send(.dismissBatchResults)
                } label: {
                    Text("Dismiss")
                        .zFont(.medium, size: 13, style: Design.Text.primary)
                }
            }
            .padding(16)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 8)
        }
    }
}

// MARK: - Helpers

extension ProposalListView {
    func voteColor(_ vote: VoteChoice?, proposal: Proposal) -> Color {
        guard let vote else { return .clear }
        return voteOptionColor(for: vote.index, total: proposal.options.count)
    }
}

private extension View {
    @ViewBuilder
    func compactPopover() -> some View {
        if #available(iOS 16.4, *) {
            self.presentationCompactAdaptation(.popover)
        } else {
            self
        }
    }
}
