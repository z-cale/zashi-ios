import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents
import VotingModels

private let tallyValueMultiplier: UInt64 = 12_500_000 // zatoshi per tally unit

private func tallyToZEC(_ value: UInt64) -> String {
    let zatoshi = value * tallyValueMultiplier
    let zec = Double(zatoshi) / 100_000_000.0
    return String(format: "%.2f ZEC", zec)
}

struct ResultsView: View {
    @Environment(\.colorScheme)
    var colorScheme

    let store: StoreOf<Voting>

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 16) {
                    // Round header card
                    roundHeaderCard()

                    // Section header
                    HStack {
                        Text("Results")
                            .zFont(.semiBold, size: 18, style: Design.Text.primary)
                        Spacer()
                    }

                    if store.isLoadingTallyResults {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading results...")
                                .zFont(.regular, size: 14, style: Design.Text.secondary)
                        }
                        .padding(.top, 20)
                    } else {
                        // Per-proposal result cards
                        ForEach(Array(store.votingRound.proposals.enumerated()), id: \.element.id) { index, proposal in
                            proposalResultCard(proposal: proposal, index: index)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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
            }
        }
    }

    // MARK: - Round Header

    private var statusLabel: String {
        switch store.activeSession?.status {
        case .active: return "Active"
        case .tallying: return "Tallying"
        case .finalized: return "Finalized"
        default: return "Unknown"
        }
    }

    private var statusColor: Color {
        switch store.activeSession?.status {
        case .active: return .green
        case .tallying: return .orange
        case .finalized: return .blue
        default: return .secondary
        }
    }

    @ViewBuilder
    private func roundHeaderCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(store.votingRound.title)
                .zFont(.semiBold, size: 18, style: Design.Text.primary)

            // Round description
            if !store.votingRound.description.isEmpty {
                Text(store.votingRound.description)
                    .zFont(.regular, size: 13, style: Design.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Detail pills
            HStack(spacing: 0) {
                detailPill(
                    label: "Snapshot",
                    value: store.votingRound.snapshotDate.formatted(date: .abbreviated, time: .omitted)
                )
                Spacer()
                detailPill(
                    label: "Ended",
                    value: store.votingRound.votingEnd.formatted(date: .abbreviated, time: .omitted)
                )
                Spacer()
                // Status pill
                VStack(spacing: 2) {
                    Text("Status")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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

    // MARK: - Proposal Result Card

    @ViewBuilder
    private func proposalResultCard(proposal: Proposal, index: Int) -> some View {
        let tally = store.tallyResults[proposal.id]
        let rawEntries = tally?.entries ?? []
        // Backfill missing options so they always display (even with 0 votes).
        let knownDecisions = Set(rawEntries.map(\.decision))
        let backfilled: [TallyResult.Entry] = proposal.options.compactMap { option in
            knownDecisions.contains(option.index) ? nil : TallyResult.Entry(decision: option.index, amount: 0)
        }
        let entries = (rawEntries + backfilled).sorted(by: { $0.decision < $1.decision })
        let totalAmount = entries.reduce(UInt64(0)) { $0 + $1.amount }
        let winningEntry = totalAmount > 0 ? entries.max(by: { $0.amount < $1.amount }) : nil

        VStack(alignment: .leading, spacing: 10) {
            // Header: number badge + title
            HStack(spacing: 8) {
                Text(String(format: "%02d", index + 1))
                    .zFont(.semiBold, size: 11, style: Design.Text.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(proposal.title)
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                    .lineLimit(2)
            }

            // Proposal description
            if !proposal.description.isEmpty {
                Text(proposal.description)
                    .zFont(.regular, size: 12, style: Design.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Result highlight + bars (group-aware)
            resultHighlightAndBars(proposal: proposal, entries: entries, totalAmount: totalAmount, winningEntry: winningEntry)

            if entries.isEmpty {
                Text("No votes recorded")
                    .zFont(.medium, size: 13, style: Design.Text.tertiary)
            }

            // Total
            if totalAmount > 0 {
                Text("Total: \(tallyToZEC(totalAmount))")
                    .zFont(.medium, size: 12, style: Design.Text.tertiary)
            }
        }
        .padding(16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Result Row

    @ViewBuilder
    private func resultRow(label: String, amount: UInt64, color: Color, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .zFont(isWinner ? .semiBold : .medium, size: 13, style: isWinner ? Design.Text.primary : Design.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(tallyToZEC(amount))
                .zFont(.medium, size: 13, style: Design.Text.primary)
                .layoutPriority(1)
        }
    }

    // MARK: - Result Highlight + Group-Aware Bars

    @ViewBuilder
    private func resultHighlightAndBars(proposal: Proposal, entries: [TallyResult.Entry], totalAmount: UInt64, winningEntry: TallyResult.Entry?) -> some View {
        let layout = buildDisplayLayout(proposal: proposal, entries: entries, winningEntry: winningEntry)

        if let winner = winningEntry, totalAmount > 0 {
            let winnerLabel = optionLabel(for: winner.decision, proposal: proposal)
            let winnerColor = layout.colorMap[winner.decision]
                ?? voteOptionColor(for: winner.decision, total: proposal.options.count)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(winnerColor)
                Text("Result: \(winnerLabel)")
                    .zFont(.semiBold, size: 14, style: Design.Text.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(winnerColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        ForEach(layout.items) { item in
            if let group = item.group {
                VStack(alignment: .leading, spacing: 6) {
                    resultRow(
                        label: group.label,
                        amount: item.amount,
                        color: item.color,
                        isWinner: false
                    )
                    ForEach(Array(group.optionIndices.enumerated()), id: \.element) { _, idx in
                        let subAmount = layout.entryByDecision[idx] ?? 0
                        let subLabel = optionLabel(for: idx, proposal: proposal)
                        let subColor = layout.colorMap[idx]
                            ?? voteOptionColor(for: idx, total: proposal.options.count)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(subColor)
                                .frame(width: 6, height: 6)
                            Text(subLabel)
                                .zFont(.regular, size: 12, style: Design.Text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(tallyToZEC(subAmount))
                                .zFont(.medium, size: 12, style: Design.Text.tertiary)
                                .layoutPriority(1)
                        }
                        .padding(.leading, 16)
                    }
                }
            } else {
                resultRow(
                    label: item.label,
                    amount: item.amount,
                    color: item.color,
                    isWinner: item.isWinner
                )
            }
        }
    }

    // MARK: - Display Layout

    private struct DisplayLayout {
        struct Item: Identifiable {
            let id: Int
            let label: String
            let amount: UInt64
            let isWinner: Bool
            let group: OptionGroup?
            let color: Color
        }
        let items: [Item]
        let colorMap: [UInt32: Color]
        let entryByDecision: [UInt32: UInt64]
    }

    private func buildDisplayLayout(proposal: Proposal, entries: [TallyResult.Entry], winningEntry: TallyResult.Entry?) -> DisplayLayout {
        let topo = GroupTopology(proposal: proposal)
        let colors = proposalColors(for: proposal)
        let entryByDecision = Dictionary(entries.map { ($0.decision, $0.amount) }, uniquingKeysWith: { a, _ in a })

        var items: [DisplayLayout.Item] = []
        for (di, entry) in topo.topLevel.enumerated() {
            let headerColor = voteOptionColor(for: UInt32(di), total: topo.topLevelCount)
            if let group = entry.group {
                let groupTotal = group.optionIndices.reduce(UInt64(0)) { $0 + (entryByDecision[$1] ?? 0) }
                items.append(.init(id: di, label: group.label, amount: groupTotal, isWinner: false, group: group, color: headerColor))
            } else {
                let label = optionLabel(for: entry.index, proposal: proposal)
                let color = colors.options[entry.index] ?? headerColor
                let amount = entryByDecision[entry.index] ?? 0
                items.append(.init(id: di, label: label, amount: amount, isWinner: entry.index == winningEntry?.decision, group: nil, color: color))
            }
        }

        return DisplayLayout(items: items, colorMap: colors.options, entryByDecision: entryByDecision)
    }

    // MARK: - Helpers

    private func optionLabel(for decision: UInt32, proposal: Proposal) -> String {
        if let option = proposal.options.first(where: { $0.index == decision }) {
            return option.label
        }
        // Fallback for proposals without explicit options
        switch decision {
        case 0: return "Support"
        case 1: return "Oppose"
        default: return "Option \(decision)"
        }
    }
}
