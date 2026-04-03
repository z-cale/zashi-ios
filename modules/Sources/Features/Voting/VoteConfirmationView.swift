import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents
import VotingModels

struct VoteConfirmationView: View {
    @Environment(\.colorScheme)
    var colorScheme

    let store: StoreOf<Voting>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ScrollView {
                    voteSummary()
                }

                Spacer()

                submitButton()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .screenTitle("Confirm Votes")
        .zashiBack {
            store.send(.goBack)
        }
        .navigationBarBackButtonHidden()
    }

    // MARK: - Vote Summary

    @ViewBuilder
    private func voteSummary() -> some View {
        let drafts = store.draftVotes.sorted { $0.key < $1.key }
        let proposals = store.votingRound.proposals

        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(drafts.count) Vote\(drafts.count == 1 ? "" : "s")")
                    .zFont(.semiBold, size: 28, style: Design.Text.primary)

                Text("\(store.votingWeightZECString) ZEC voting weight")
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            ForEach(drafts, id: \.key) { proposalId, choice in
                if let proposal = proposals.first(where: { $0.id == proposalId }) {
                    voteRow(proposal: proposal, choice: choice)
                }
            }
        }
    }

    @ViewBuilder
    private func voteRow(proposal: Proposal, choice: VoteChoice) -> some View {
        let optionLabel = proposal.options.first { $0.index == choice.index }?.label ?? "Option \(choice.index + 1)"
        let color = voteOptionColor(for: choice.index, total: proposal.options.count)
        let icon = voteOptionIcon(for: choice.index, total: proposal.options.count)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title)
                    .zFont(.medium, size: 15, style: Design.Text.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                    Text(optionLabel)
                        .zFont(.semiBold, size: 13, style: Design.Text.primary)
                }
                .foregroundStyle(color)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Submit Button

    @ViewBuilder
    private func submitButton() -> some View {
        let count = store.draftVotes.count

        ZashiButton("Submit \(count) Vote\(count == 1 ? "" : "s")") {
            store.send(.confirmVoteSubmission)
        }
    }
}
