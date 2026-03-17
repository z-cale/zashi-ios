import SwiftUI
import Generated
import UIComponents

// MARK: - Data Model

private struct DemoVote: Identifiable, Equatable {
    let id: String
    let proposalName: String
    let choice: String
    let totalShares = 5
    var sharesReceived: Int
    var sharesSubmitted: Int

    var phase: VotePhase {
        if sharesSubmitted == totalShares { return .complete }
        if sharesReceived < totalShares { return .sending }
        if sharesSubmitted > 0 { return .submitting }
        return .received
    }

    var statusColor: Color {
        switch phase {
        case .sending: return .blue
        case .received, .submitting: return .orange
        case .complete: return .green
        }
    }

    var isComplete: Bool { sharesSubmitted == totalShares }

    @discardableResult
    mutating func advanceOne() -> Bool {
        if sharesReceived < totalShares {
            sharesReceived += 1
            return true
        }
        if sharesSubmitted < totalShares {
            sharesSubmitted += 1
            return true
        }
        return false
    }

    mutating func reset() {
        sharesReceived = 0
        sharesSubmitted = 0
    }
}

private enum VotePhase {
    case sending, received, submitting, complete
}

// MARK: - Initial Demo Data

private let initialVotes: [DemoVote] = [
    DemoVote(
        id: "sprout",
        proposalName: "Sprout Deprecation",
        choice: "Immediately upon NU7 activation",
        sharesReceived: 5, sharesSubmitted: 5
    ),
    DemoVote(
        id: "memo",
        proposalName: "Memo Bundles",
        choice: "Yes — 16 KiB memo size limit",
        sharesReceived: 5, sharesSubmitted: 3
    ),
    DemoVote(
        id: "fee",
        proposalName: "Fee Burn",
        choice: "Yes — 60% of fees burned",
        sharesReceived: 5, sharesSubmitted: 0
    ),
    DemoVote(
        id: "nsm",
        proposalName: "NSM Activation",
        choice: "Support activation",
        sharesReceived: 2, sharesSubmitted: 0
    ),
]

// MARK: - Root View

struct ShareSubmissionDemoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var votes = initialVotes
    @State private var selectedIndex: Int?
    @State private var autoPlaying = false

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
                        Text("After you cast a vote, it is split into encrypted shares distributed to helper servers. Each server submits its share to the blockchain over a period of days to protect your privacy.")
                            .zFont(.regular, size: 14, style: Design.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        ForEach(Array(votes.enumerated()), id: \.element.id) { index, vote in
                            VoteStatusCard(vote: vote, colorScheme: colorScheme)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIndex = index }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }

                simulationControls()
            }
            .navigationTitle("Share Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: isDetailPresented) {
                if let idx = selectedIndex, idx < votes.count {
                    VoteSubmissionDetailView(vote: $votes[idx])
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
                    stepNextVote()
                } label: {
                    Label("Step", systemImage: "forward.frame.fill")
                        .zFont(.medium, size: 14, style: Design.Text.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(votes.allSatisfy(\.isComplete))

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
                .disabled(votes.allSatisfy(\.isComplete) && !autoPlaying)

                Spacer()

                Button {
                    autoPlaying = false
                    withAnimation { votes = initialVotes }
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

    private func stepNextVote() {
        withAnimation(.easeInOut(duration: 0.3)) {
            for i in votes.indices {
                if votes[i].advanceOne() { return }
            }
        }
    }

    private func scheduleAutoStep() {
        guard autoPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard autoPlaying else { return }
            let incomplete = votes.enumerated().filter { !$0.element.isComplete }
            if let pick = incomplete.randomElement() {
                withAnimation(.easeInOut(duration: 0.3)) {
                    votes[pick.offset].advanceOne()
                }
                scheduleAutoStep()
            } else {
                autoPlaying = false
            }
        }
    }
}

// MARK: - Vote Status Card (list item)

private struct VoteStatusCard: View {
    let vote: DemoVote
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vote.proposalName)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)
                    Text(vote.choice)
                        .zFont(.regular, size: 13, style: Design.Text.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Text.tertiary.color(colorScheme))
            }

            HStack(spacing: 16) {
                MiniProgress(
                    label: "Received",
                    filled: vote.sharesReceived,
                    total: vote.totalShares,
                    color: vote.sharesReceived == vote.totalShares ? .green : .blue
                )

                MiniProgress(
                    label: "Submitted",
                    filled: vote.sharesSubmitted,
                    total: vote.totalShares,
                    color: vote.sharesSubmitted == vote.totalShares ? .green : .orange
                )
            }
        }
        .padding(16)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(vote.statusColor.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Mini Progress (compact bar + label)

private struct MiniProgress: View {
    let label: String
    let filled: Int
    let total: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) \(filled)/\(total)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(filled == total ? .green : .secondary)

            HStack(spacing: 2) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < filled ? color : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
        }
    }
}

// MARK: - Detail View

private struct VoteSubmissionDetailView: View {
    @Binding var vote: DemoVote
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            scrollContent()
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
                                _ = vote.advanceOne()
                            }
                        } label: {
                            Image(systemName: "forward.frame.fill")
                                .font(.system(size: 14))
                        }
                        .disabled(vote.isComplete)

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                vote.reset()
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

    // MARK: - Scroll Content

    @ViewBuilder
    private func scrollContent() -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                voteHeader()

                phaseCard(
                    title: "Delivery to Helpers",
                    icon: "arrow.up.circle.fill",
                    filled: vote.sharesReceived,
                    total: vote.totalShares,
                    activeColor: .blue,
                    doneMessage: "All shares delivered",
                    activeMessage: "Sending shares to helper servers…",
                    waitingMessage: nil,
                    isActive: vote.sharesReceived < vote.totalShares
                )

                HStack {
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    Spacer()
                }

                phaseCard(
                    title: "Submission to Chain",
                    icon: "link.circle.fill",
                    filled: vote.sharesSubmitted,
                    total: vote.totalShares,
                    activeColor: .orange,
                    doneMessage: "All shares on-chain",
                    activeMessage: "Helper servers submitting to blockchain…",
                    waitingMessage: "Waiting for delivery to complete…",
                    isActive: vote.sharesReceived == vote.totalShares
                        && vote.sharesSubmitted < vote.totalShares
                )

                if vote.isComplete {
                    completeBanner()
                } else {
                    infoNote()
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func voteHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vote.proposalName)
                .zFont(.semiBold, size: 22, style: Design.Text.primary)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                Text(vote.choice)
                    .zFont(.medium, size: 15, style: Design.Text.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Phase Card

    @ViewBuilder
    private func phaseCard(
        title: String,
        icon: String,
        filled: Int,
        total: Int,
        activeColor: Color,
        doneMessage: String,
        activeMessage: String,
        waitingMessage: String?,
        isActive: Bool
    ) -> some View {
        let isDone = filled == total
        let displayColor = isDone ? Color.green : activeColor
        let isWaiting = !isActive && !isDone

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(displayColor)

                Text(title)
                    .zFont(.semiBold, size: 17, style: Design.Text.primary)

                Spacer()

                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            // Segmented bar
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < filled ? displayColor : Color.secondary.opacity(0.15))
                        .frame(height: 8)
                }
            }

            // Status line
            HStack {
                if isActive {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 2)
                }

                if isDone {
                    Text(doneMessage)
                        .zFont(.regular, size: 13, style: Design.Text.secondary)
                } else if isWaiting {
                    Text(waitingMessage ?? "")
                        .zFont(.regular, size: 13, style: Design.Text.tertiary)
                } else {
                    Text(activeMessage)
                        .zFont(.regular, size: 13, style: Design.Text.tertiary)
                }

                Spacer()

                Text("\(filled)/\(total)")
                    .zFont(.medium, size: 13, style: Design.Text.tertiary)
            }
        }
        .padding(16)
        .background(displayColor.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(displayColor.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Footer Banners

    @ViewBuilder
    private func infoNote() -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue.opacity(0.7))
                .font(.system(size: 16))

            Text("Shares are submitted to the blockchain over several days. This delay is intentional and protects your voting privacy.")
                .zFont(.regular, size: 13, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func completeBanner() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vote fully submitted")
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                Text("All shares have been posted to the blockchain.")
                    .zFont(.regular, size: 13, style: Design.Text.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview("Share Submission Demo") {
    ShareSubmissionDemoView()
}
