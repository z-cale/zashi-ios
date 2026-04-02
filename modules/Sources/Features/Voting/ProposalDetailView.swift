import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents
import VotingModels

struct ProposalDetailView: View {
    @Environment(\.colorScheme)
    var colorScheme

    let store: StoreOf<Voting>
    let proposal: Proposal

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    @State private var now = Date()
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
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            if let zip = proposal.zipNumber {
                                ZIPBadge(zipNumber: zip)
                            }

                            Text(proposal.title)
                                .zFont(.semiBold, size: 22, style: Design.Text.primary)

                            Text(proposal.description)
                                .zFont(.regular, size: 15, style: Design.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Forum link
                        if let url = proposal.forumURL {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bubble.left.and.text.bubble.right")
                                        .font(.caption)
                                    Text("View Forum Discussion")
                                        .zFont(.medium, size: 14, style: Design.Text.link)
                                }
                            }
                        }

                        Spacer().frame(height: 8)

                        // Vote section
                        voteSection()

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

            }
            .navigationTitle(positionLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.send(.backToList)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("List")
                                .font(.system(size: 16))
                        }
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
        }
    }

    private var positionLabel: String {
        if let index = store.detailProposalIndex {
            return "\(index + 1) of \(store.totalProposals)"
        }
        return "Proposal"
    }

    // MARK: - Vote Section

    @ViewBuilder
    private func voteSection() -> some View {
        let confirmedVote = store.votes[proposal.id]
        let draftChoice = store.draftVotes[proposal.id]
        let isSubmittingThis = store.isBatchSubmitting && store.submittingProposalId == proposal.id

        VStack(spacing: 12) {
            if let confirmed = confirmedVote {
                // Already submitted (from this or a previous batch)
                if isSubmittingThis {
                    submittingBanner(choice: confirmed)
                } else {
                    confirmedBanner(choice: confirmed)
                }
            } else if isSubmittingThis, let draft = draftChoice {
                submittingBanner(choice: draft)
            } else {
                // Show draft banner if a draft exists
                if let draft = draftChoice {
                    draftBanner(choice: draft)
                }

                // Show batch error for this proposal if any
                if let error = store.batchVoteErrors[proposal.id] {
                    voteErrorBanner(error: error, proposalId: proposal.id)
                }

                // Always show vote buttons so the user can pick or change
                let buttonsDisabled = store.isBatchSubmitting
                ForEach(proposal.options, id: \.index) { option in
                    let choice = VoteChoice.option(option.index)
                    voteButton(
                        title: option.label,
                        icon: voteOptionIcon(for: option.index, total: proposal.options.count),
                        color: voteOptionColor(for: option.index, total: proposal.options.count),
                        isSelected: draftChoice == choice,
                        enabled: !buttonsDisabled
                    ) {
                        store.send(.castVote(proposalId: proposal.id, choice: choice))
                    }
                }

                // Skip button — go back without drafting
                if !buttonsDisabled {
                    Button {
                        if draftChoice != nil {
                            store.send(.clearDraftVote(proposalId: proposal.id))
                        }
                        store.send(.backToList)
                    } label: {
                        HStack {
                            Image(systemName: "forward.fill")
                            Text("Skip")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func draftBanner(choice: VoteChoice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(voteColor(choice))
            VStack(alignment: .leading, spacing: 2) {
                Text("Draft vote")
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                Text(optionLabel(for: choice))
                    .zFont(.medium, size: 14, style: Design.Text.secondary)
            }
            Spacer()
            Button {
                store.send(.clearDraftVote(proposalId: proposal.id))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(voteColor(choice).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(voteColor(choice).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
        )
    }

    @ViewBuilder
    private func confirmedBanner(choice: VoteChoice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(voteColor(choice))
            VStack(alignment: .leading, spacing: 2) {
                Text("Vote recorded")
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                Text(optionLabel(for: choice))
                    .zFont(.medium, size: 14, style: Design.Text.secondary)
            }
            Spacer()
            VoteChip(
                choice: choice,
                label: optionLabel(for: choice),
                color: voteColor(choice)
            )
        }
        .padding(16)
        .background(voteColor(choice).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(voteColor(choice).opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func submittingBanner(choice: VoteChoice) -> some View {
        let step = store.voteSubmissionStep
        let stepNum = step?.stepNumber ?? 1
        let totalSteps = Voting.State.VoteSubmissionStep.totalSteps
        let stepLabel = store.voteSubmissionStepLabel ?? "Submitting vote..."

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(stepLabel)
                        .zFont(.semiBold, size: 15, style: Design.Text.primary)
                    Text("Step \(stepNum) of \(totalSteps)")
                        .zFont(.regular, size: 12, style: Design.Text.tertiary)
                }
                Spacer()
                VoteChip(
                    choice: choice,
                    label: optionLabel(for: choice),
                    color: voteColor(choice)
                )
            }

            // Step progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(voteColor(choice).opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(voteColor(choice))
                        .frame(width: geo.size.width * Double(stepNum) / Double(totalSteps))
                        .animation(.easeInOut(duration: 0.3), value: stepNum)
                }
            }
            .frame(height: 3)
        }
        .padding(16)
        .background(voteColor(choice).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(voteColor(choice).opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func voteErrorBanner(error: String, proposalId: UInt32) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vote submission failed")
                        .zFont(.semiBold, size: 15, style: Design.Text.primary)
                    Text(error)
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
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Components

extension ProposalDetailView {
    @ViewBuilder
    func voteButton(
        title: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            impactFeedback.impactOccurred()
            action()
        } label: {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? .white : color)
            .background(isSelected ? color : color.opacity(enabled ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    func voteColor(_ choice: VoteChoice) -> Color {
        voteOptionColor(for: choice.index, total: proposal.options.count)
    }

    func optionLabel(for choice: VoteChoice) -> String {
        proposal.options.first { $0.index == choice.index }?.label ?? "Option \(choice.index)"
    }
}
