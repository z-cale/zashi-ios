import SwiftUI
import Generated
import UIComponents
import VotingModels

// MARK: - Prototype Banner

struct PrototypeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.caption)
            Text("Prototype \u{2014} some features are mocked")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Vote Option Palette

/// Color for a vote option index. For 2-option proposals this preserves the classic
/// green (Support) / red (Oppose) look; for 3+ options it cycles through a palette.
func voteOptionColor(for index: UInt32, total: Int) -> Color {
    if total == 2 { return index == 0 ? .green : .red }
    let palette: [Color] = [.green, .red, .blue, .purple, .orange, .teal, .pink, .indigo]
    return palette[Int(index) % palette.count]
}

// MARK: - Group Topology

/// Pre-computes the display-order topology for a proposal's option groups.
/// Computed once and shared across color mapping, vote selection, and results display.
struct GroupTopology {
    struct Item {
        let index: UInt32
        let group: OptionGroup?
    }
    let groupedIndices: Set<UInt32>
    let groupByFirst: [UInt32: OptionGroup]
    let topLevel: [Item]
    var topLevelCount: Int { topLevel.count }

    init(proposal: Proposal) {
        groupedIndices = Set(proposal.optionGroups.flatMap(\.optionIndices))
        groupByFirst = Dictionary(
            proposal.optionGroups.compactMap { g in g.optionIndices.min().map { ($0, g) } },
            uniquingKeysWith: { a, _ in a }
        )
        var items: [Item] = []
        for option in proposal.options.sorted(by: { $0.index < $1.index }) {
            if let group = groupByFirst[option.index] {
                items.append(Item(index: option.index, group: group))
            } else if !groupedIndices.contains(option.index) {
                items.append(Item(index: option.index, group: nil))
            }
        }
        topLevel = items
    }
}

// MARK: - Proposal Color Scheme

/// All colors derived from a proposal's group topology. Computed once and shared
/// across vote selection, list chips, and results display.
struct ProposalColors {
    /// Option index → color for individual vote options (sub-options get sub-palette slots).
    let options: [UInt32: Color]
    /// Group ID → display-order header color for group rows.
    let groupHeaders: [UInt32: Color]
}

func proposalColors(for proposal: Proposal) -> ProposalColors {
    guard !proposal.optionGroups.isEmpty else {
        let map = Dictionary(uniqueKeysWithValues: proposal.options.map {
            ($0.index, voteOptionColor(for: $0.index, total: proposal.options.count))
        })
        return ProposalColors(options: map, groupHeaders: [:])
    }

    let topo = GroupTopology(proposal: proposal)
    let totalSubOptions = topo.topLevel.compactMap(\.group).reduce(0) { $0 + $1.optionIndices.count }
    let colorSlots = topo.topLevelCount + totalSubOptions

    var optionColors: [UInt32: Color] = [:]
    var groupColors: [UInt32: Color] = [:]
    var subOffset = topo.topLevelCount
    for (di, item) in topo.topLevel.enumerated() {
        let topColor = voteOptionColor(for: UInt32(di), total: topo.topLevelCount)
        if let group = item.group {
            groupColors[group.id] = topColor
            for (si, idx) in group.optionIndices.enumerated() {
                optionColors[idx] = voteOptionColor(for: UInt32(subOffset + si), total: colorSlots)
            }
            subOffset += group.optionIndices.count
        } else {
            optionColors[item.index] = topColor
        }
    }
    return ProposalColors(options: optionColors, groupHeaders: groupColors)
}

/// SF Symbol for a vote option index. For 2-option proposals this preserves the classic
/// thumbs-up / thumbs-down icons; for 3+ options it uses numbered circles.
func voteOptionIcon(for index: UInt32, total: Int) -> String {
    if total == 2 { return index == 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill" }
    return "\(index + 1).circle.fill"
}

// MARK: - Vote Chip

struct VoteChip: View {
    let choice: VoteChoice?
    var label: String?
    var color: Color?

    var body: some View {
        Text(resolvedLabel)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(choice != nil ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(resolvedBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: choice == nil ? 1 : 0)
            )
    }

    private var resolvedLabel: String {
        if let label { return label }
        guard choice != nil else { return "Not voted" }
        return "Voted"
    }

    private var resolvedBackground: Color {
        if let color { return color }
        guard choice != nil else { return .clear }
        return .gray
    }

    private var borderColor: Color {
        choice == nil ? Color.secondary.opacity(0.3) : .clear
    }
}

// MARK: - ZIP Badge

struct ZIPBadge: View {
    let zipNumber: String

    var body: some View {
        Text(zipNumber)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - ZKP Status Banner

struct ZKPStatusBanner: View {
    let proofStatus: ProofStatus
    var isPreparingWitnesses: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            switch proofStatus {
            case .notStarted:
                EmptyView()
            case .generating(let progress):
                ProgressView()
                    .scaleEffect(0.8)
                if isPreparingWitnesses {
                    Text("Preparing note witnesses...")
                        .font(.caption)
                } else {
                    Text("Preparing voting authorization... \(Int(progress * 100))%")
                        .font(.caption)
                }
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Ready to vote")
                    .font(.caption)
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(error)
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Vote Commitment Stub Card

struct VoteCommitmentStubCard: View {
    let bundle: VoteCommitmentBundle
    let txHash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prototype VC Stub")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("commitment: \(bundle.voteCommitment.shortHex)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text("van nullifier: \(bundle.vanNullifier.shortHex)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            if let txHash, !txHash.isEmpty {
                Text("tx: \(txHash)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension Data {
    var shortHex: String {
        let hex = map { String(format: "%02x", $0) }.joined()
        if hex.count <= 16 {
            return hex
        }
        let prefix = hex.prefix(8)
        let suffix = hex.suffix(8)
        return "\(prefix)...\(suffix)"
    }
}
