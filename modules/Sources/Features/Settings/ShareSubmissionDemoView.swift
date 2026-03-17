import SwiftUI
import Generated
import UIComponents

// MARK: - Data Model

private struct DemoProposal: Identifiable, Equatable {
    let id: String
    let title: String
    let choice: String
    var status: VoteStatus
    var chainProgress: Double // 0.0–1.0 — how much is confirmed on chain
    var willFail: Bool = false

    var isTerminal: Bool {
        status == .confirmed || status == .failed
    }
}

private enum VoteStatus: Equatable {
    case preparing   // client building proof
    case submitted   // sent to servers, awaiting chain confirmation
    case confirmed   // all confirmed on chain
    case failed      // retries exhausted

    var label: String {
        switch self {
        case .preparing: return "Preparing"
        case .submitted: return "Submitted"
        case .confirmed: return "Confirmed"
        case .failed: return "Needs Attention"
        }
    }

    var icon: String {
        switch self {
        case .preparing: return "circle.dotted"
        case .submitted: return "checkmark.circle"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .preparing: return .secondary
        case .submitted, .confirmed: return .green
        case .failed: return .orange
        }
    }
}

// MARK: - Initial Demo Data

private let initialProposals: [DemoProposal] = [
    DemoProposal(
        id: "sprout",
        title: "Sprout Deprecation",
        choice: "Immediately upon NU7 activation",
        status: .confirmed,
        chainProgress: 1.0
    ),
    DemoProposal(
        id: "memo",
        title: "Memo Bundles",
        choice: "Yes — 16 KiB memo size limit",
        status: .submitted,
        chainProgress: 0.6
    ),
    DemoProposal(
        id: "fee",
        title: "Fee Burn",
        choice: "Yes — 60% of fees burned",
        status: .submitted,
        chainProgress: 0.0
    ),
    DemoProposal(
        id: "nsm",
        title: "NSM Activation",
        choice: "Support activation",
        status: .preparing,
        chainProgress: 0.0
    ),
    DemoProposal(
        id: "blocktime",
        title: "Lower Block Times",
        choice: "Yes — reduce to 30 seconds",
        status: .submitted,
        chainProgress: 0.75,
        willFail: true
    ),
]

// MARK: - Root View

struct ShareSubmissionDemoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var proposals = initialProposals
    @State private var selectedIndex: Int?
    @State private var autoPlaying = false
    @State private var expandedInfoId: String?

    private var isDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedIndex != nil },
            set: { if !$0 { selectedIndex = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Status is shown per proposal while the voting round stays active.")
                            .zFont(.regular, size: 14, style: Design.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                            ProposalStatusCard(
                                proposal: proposal,
                                colorScheme: colorScheme,
                                isInfoExpanded: expandedInfoId == proposal.id,
                                onInfoToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedInfoId = expandedInfoId == proposal.id ? nil : proposal.id
                                    }
                                },
                                onRetry: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proposals[index].status = .submitted
                                        proposals[index].willFail = false
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedIndex = index }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }

                simulationControls()
            }
            .navigationTitle("Vote Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: isDetailPresented) {
                if let idx = selectedIndex, idx < proposals.count {
                    VoteStatusDetailView(proposal: $proposals[idx])
                }
            }
        }
        .onDisappear { autoPlaying = false }
    }

    // MARK: - Simulation Controls

    @ViewBuilder
    private func simulationControls() -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                Button {
                    stepNext()
                } label: {
                    Label("Step", systemImage: "forward.frame.fill")
                        .zFont(.medium, size: 14, style: Design.Text.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(proposals.allSatisfy(\.isTerminal))

                Button {
                    autoPlaying.toggle()
                    if autoPlaying { scheduleAutoStep() }
                } label: {
                    Label(
                        autoPlaying ? "Pause" : "Auto",
                        systemImage: autoPlaying ? "pause.fill" : "play.fill"
                    )
                    .zFont(.medium, size: 14, style: Design.Text.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(autoPlaying ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(proposals.allSatisfy(\.isTerminal) && !autoPlaying)

                Spacer()

                Button {
                    autoPlaying = false
                    expandedInfoId = nil
                    withAnimation { proposals = initialProposals }
                } label: {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                        .zFont(.medium, size: 13, style: Design.Text.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
    }

    private func stepNext() {
        withAnimation(.easeInOut(duration: 0.3)) {
            // Advance the first non-terminal proposal (sequential order)
            for i in proposals.indices where !proposals[i].isTerminal {
                advanceProposal(at: i)
                return
            }
        }
    }

    private func scheduleAutoStep() {
        guard autoPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard autoPlaying else { return }
            let nonTerminal = proposals.enumerated().filter { !$0.element.isTerminal }
            if let pick = nonTerminal.randomElement() {
                withAnimation(.easeInOut(duration: 0.3)) {
                    advanceProposal(at: pick.offset)
                }
                scheduleAutoStep()
            } else {
                autoPlaying = false
            }
        }
    }

    private func advanceProposal(at index: Int) {
        switch proposals[index].status {
        case .preparing:
            proposals[index].status = .submitted
        case .submitted:
            if proposals[index].willFail && proposals[index].chainProgress >= 0.6 {
                proposals[index].status = .failed
                return
            }
            let increment = Double.random(in: 0.15...0.30)
            proposals[index].chainProgress = min(1.0, proposals[index].chainProgress + increment)
            if proposals[index].chainProgress >= 1.0 {
                proposals[index].chainProgress = 1.0
                proposals[index].status = .confirmed
            }
        case .confirmed, .failed:
            break
        }
    }
}

// MARK: - Proposal Status Card

private struct ProposalStatusCard: View {
    let proposal: DemoProposal
    let colorScheme: ColorScheme
    let isInfoExpanded: Bool
    let onInfoToggle: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)
                    Text(proposal.choice)
                        .zFont(.regular, size: 13, style: Design.Text.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Text.tertiary.color(colorScheme))
            }

            // Status badge
            statusBadge()

            // Progress bar (submitted with chain progress, or failed)
            if showsProgressBar {
                progressBar()
            }

            // Inline info expansion
            if isInfoExpanded && proposal.status == .submitted {
                infoContent()
            }
        }
        .padding(16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(proposal.status.color.opacity(0.2), lineWidth: 1)
        )
    }

    private var showsProgressBar: Bool {
        switch proposal.status {
        case .submitted: return proposal.chainProgress > 0
        case .failed: return true
        default: return false
        }
    }

    @ViewBuilder
    private func statusBadge() -> some View {
        HStack(spacing: 8) {
            if proposal.status == .preparing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: proposal.status.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(proposal.status.color)
            }

            Text(proposal.status.label)
                .zFont(.medium, size: 14, style: proposal.status == .preparing
                    ? Design.Text.secondary : Design.Text.primary)

            Spacer()

            // Info button for submitted with progress
            if proposal.status == .submitted && proposal.chainProgress > 0 {
                Button {
                    onInfoToggle()
                } label: {
                    Image(systemName: isInfoExpanded ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Retry for failed
            if proposal.status == .failed {
                Button {
                    onRetry()
                } label: {
                    Text("Retry")
                        .zFont(.medium, size: 13, style: Design.Text.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func progressBar() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(proposal.status == .failed ? Color.orange : Color.green)
                        .frame(width: geo.size.width * proposal.chainProgress)
                        .animation(.easeInOut(duration: 0.3), value: proposal.chainProgress)
                }
            }
            .frame(height: 4)

            Text(proposal.status == .failed
                ? "Confirmation incomplete"
                : "Privately confirming on chain")
                .zFont(.regular, size: 11, style: Design.Text.tertiary)
        }
    }

    @ViewBuilder
    private func infoContent() -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text("Your vote is being privately confirmed on the blockchain over time to protect your voting privacy. No action needed.")
                .zFont(.regular, size: 12, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Detail View

private struct VoteStatusDetailView: View {
    @Binding var proposal: DemoProposal
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    voteHeader()
                    statusSection()

                    if proposal.status != .confirmed {
                        privacyExplanation()
                    }

                    if proposal.status == .failed {
                        failedActions()
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle("Vote Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                advanceInDetail()
                            }
                        } label: {
                            Image(systemName: "forward.frame.fill")
                                .font(.system(size: 14))
                        }
                        .disabled(proposal.isTerminal)

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proposal.status = .preparing
                                proposal.chainProgress = 0
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func voteHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title)
                .zFont(.semiBold, size: 22, style: Design.Text.primary)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text(proposal.choice)
                    .zFont(.medium, size: 15, style: Design.Text.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Status Section

    @ViewBuilder
    private func statusSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(proposal.status.color.opacity(0.12))
                        .frame(width: 44, height: 44)

                    if proposal.status == .preparing {
                        ProgressView()
                    } else {
                        Image(systemName: proposal.status.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(proposal.status.color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.status.label)
                        .zFont(.semiBold, size: 18, style: Design.Text.primary)
                    Text(statusDescription)
                        .zFont(.regular, size: 14, style: Design.Text.secondary)
                }
            }

            if proposal.status == .submitted || proposal.status == .failed {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.12))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(proposal.status == .failed ? Color.orange : Color.green)
                                .frame(width: geo.size.width * proposal.chainProgress)
                                .animation(.easeInOut(duration: 0.3), value: proposal.chainProgress)
                        }
                    }
                    .frame(height: 6)

                    if proposal.chainProgress > 0 {
                        Text(progressLabel)
                            .zFont(.regular, size: 12, style: Design.Text.tertiary)
                    }
                }
            }
        }
        .padding(20)
        .background(proposal.status.color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(proposal.status.color.opacity(0.15), lineWidth: 1)
        )
    }

    private var statusDescription: String {
        switch proposal.status {
        case .preparing:
            return "Building your vote proof"
        case .submitted:
            return proposal.chainProgress > 0
                ? "Privately confirming on chain"
                : "Your vote has been submitted"
        case .confirmed:
            return "Confirmed on the blockchain"
        case .failed:
            return "Confirmation could not be completed"
        }
    }

    private var progressLabel: String {
        let pct = Int(proposal.chainProgress * 100)
        if proposal.status == .failed {
            return "\(pct)% confirmed before failure"
        }
        return "\(pct)% confirmed on chain"
    }

    // MARK: - Privacy Explanation

    @ViewBuilder
    private func privacyExplanation() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.blue.opacity(0.7))
                    .font(.system(size: 16))
                Text("Why does this take time?")
                    .zFont(.semiBold, size: 14, style: Design.Text.primary)
            }

            Text("To protect your privacy, your vote is distributed to the blockchain incrementally over several days. This prevents observers from determining your full voting weight.\n\nNo action is needed — this happens automatically in the background.")
                .zFont(.regular, size: 13, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.blue.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Failed Actions

    @ViewBuilder
    private func failedActions() -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proposal.status = .submitted
                    proposal.willFail = false
                }
            } label: {
                Text("Retry Submission")
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                // No-op in demo
            } label: {
                Text("Contact Support")
                    .zFont(.medium, size: 14, style: Design.Text.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Simulation

    private func advanceInDetail() {
        switch proposal.status {
        case .preparing:
            proposal.status = .submitted
        case .submitted:
            if proposal.willFail && proposal.chainProgress >= 0.6 {
                proposal.status = .failed
                return
            }
            let increment = Double.random(in: 0.15...0.30)
            proposal.chainProgress = min(1.0, proposal.chainProgress + increment)
            if proposal.chainProgress >= 1.0 {
                proposal.chainProgress = 1.0
                proposal.status = .confirmed
            }
        case .confirmed, .failed:
            break
        }
    }
}

// MARK: - Preview

#Preview("Vote Status Demo") {
    ShareSubmissionDemoView()
}
