import SwiftUI
import Combine
import ComposableArchitecture
import Generated
import UIComponents
import VotingModels

struct ProposalListView: View {
    enum Mode { case voting, review }

    @Environment(\.colorScheme)
    var colorScheme
    @State private var now = Date()
    @State private var descriptionExpanded = false

    let store: StoreOf<Voting>
    var mode: Mode = .voting

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                if store.activeSession == nil {
                    noActiveRoundCard()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    proposalScrollView()
                }
            }
            .applyScreenBackground()
            .screenTitle("Coinholder Polling")
            .zashiBack { store.send(.backToList) }
            .overlay(alignment: .bottom) {
                bottomCTA()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
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
                VStack(alignment: .leading, spacing: 24) {
                    switch mode {
                    case .voting:
                        overviewHeader()
                    case .review:
                        reviewHeader()
                    }

                    VStack(spacing: 16) {
                        ForEach(store.votingRound.proposals) { proposal in
                            proposalCard(proposal)
                                .id(proposal.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                // Pushes the title down from the COINHOLDER POLLING navbar to
                // match the design's breathing room. The padding lives at the
                // ScrollView content level (rather than on the title row's
                // top) because SwiftUI tends to absorb padding on the first
                // child of a VStack-inside-ScrollView via safe-area insets.
                .padding(.top, 24)
                // Bottom inset large enough to scroll the last proposal card
                // out from under the floating CTA. Approx button height (~50)
                // + outer padding (~16) + breathing room.
                .padding(.bottom, 96)
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

    // MARK: - Review Header

    @ViewBuilder
    private func reviewHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review and submit vote")
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .tracking(-0.384)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tap on the question to edit any of your answers. After you review your answers, tap on Confirm & Submit.")
                .zFont(size: 14, style: Design.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Overview Header

    @ViewBuilder
    private func overviewHeader() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row: round title (left) + #snapshotHeight (right).
            // Negative top padding nudges the title up to absorb Inter's
            // natural line-leading at 20pt and tighten the gap from the
            // COINHOLDER POLLING navbar title.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(store.votingRound.title)
                    .zFont(.semiBold, size: 20, style: Design.Text.primary)
                    .tracking(-0.32) // -1.6% × 20pt
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let session = store.activeSession {
                    Text("#\(formattedSnapshotHeight(session.snapshotHeight))")
                        .zFont(.medium, size: 20, style: Design.Text.primary)
                        .tracking(-0.32)
                        .fixedSize()
                }
            }

            voteProgressBar()

            // Meta line: Ends X · Voting Power Y · N days left
            // Single line — scale down slightly if all three pieces don't quite
            // fit (e.g. when "Voting Power 0.750 ZEC" + a long date pushes the
            // line just past the available width).
            Text(metaLine)
                .zFont(.medium, size: 12, style: Design.Text.tertiary)
                .tracking(-0.072) // -0.6% × 12pt
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)

            // Description with View more toggle. Collapsed to one line by
            // default; tapping "View more" expands to the full description.
            if !store.votingRound.description.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.votingRound.description)
                        .zFont(size: 14, style: Design.Text.primary)
                        .lineLimit(descriptionExpanded ? nil : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    viewMoreButton()
                }
            }
        }
    }

    @ViewBuilder
    private func viewMoreButton() -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                descriptionExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(descriptionExpanded ? "View less" : "View more")
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    .tracking(-0.224)
                Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.Text.tertiary.color(colorScheme))
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Design.Surfaces.bgSecondary.color(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius._md))
        }
    }

    // MARK: - Vote Progress Bar

    @ViewBuilder
    private func voteProgressBar() -> some View {
        let total = max(store.totalProposals, 1)
        let drafted = store.draftVotes.count
        let ratio = Double(drafted) / Double(total)

        GeometryReader { geo in
            let barHeight: CGFloat = 10
            let knobDiameter: CGFloat = 10
            let dotDiameter: CGFloat = 4
            // Reserve half the knob on each side so the knob can sit fully
            // inside the bar at 0% and 100% without clipping.
            let usableWidth = geo.size.width - knobDiameter
            let leadingInset = knobDiameter / 2

            ZStack(alignment: .leading) {
                // Solid capsule — the bar background.
                Capsule()
                    .fill(Design.Surfaces.bgTertiary.color(colorScheme))
                    .frame(height: barHeight)

                // Per-proposal dots inside the bar, slightly darker than the
                // bar background so they read as markers without competing
                // with the knob.
                ForEach(0..<total, id: \.self) { index in
                    let position: CGFloat = total <= 1
                        ? 0
                        : usableWidth * (CGFloat(index) / CGFloat(total - 1))
                    Circle()
                        .fill(Design.Text.tertiary.color(colorScheme).opacity(0.35))
                        .frame(width: dotDiameter, height: dotDiameter)
                        .offset(x: leadingInset + position - dotDiameter / 2)
                }

                // Knob — black playhead at the current vote progress.
                Circle()
                    .fill(Design.Text.primary.color(colorScheme))
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: usableWidth * ratio)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    // MARK: - Meta Line

    private var metaLine: String {
        let endsString: String
        let votingPowerString: String
        let timeLeftString: String

        if let session = store.activeSession {
            let endsFormatter = DateFormatter()
            endsFormatter.dateFormat = "MMM d, yyyy"
            endsString = "Ends \(endsFormatter.string(from: session.voteEndTime))"
        } else {
            endsString = ""
        }

        votingPowerString = "Voting Power \(store.votingWeightZECString) ZEC"
        timeLeftString = timeLeftLabel

        return [endsString, votingPowerString, timeLeftString]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }

    private var timeLeftLabel: String {
        guard let session = store.activeSession else { return "" }
        let remaining = session.voteEndTime.timeIntervalSince(now)
        guard remaining > 0 else { return "Ended" }

        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        // Days uses long form to match the design ("4 days left").
        // Hours/minutes use compact forms so the meta line doesn't wrap when
        // the round is in its final stretch.
        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") left"
        } else if hours > 0 {
            return "\(hours)h left"
        } else {
            return "\(minutes)m left"
        }
    }

    /// Formats the snapshot block height with comma grouping regardless of the
    /// device locale, so it always reads "#2,800,000" rather than "#2 800 000"
    /// on locales with non-breaking-space groupers.
    private func formattedSnapshotHeight(_ height: UInt64) -> String {
        height.formatted(.number.locale(Locale(identifier: "en_US")).grouping(.automatic))
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
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Card

extension ProposalListView {
    @ViewBuilder
    func proposalCard(_ proposal: Proposal) -> some View {
        let choice = store.draftVotes[proposal.id] ?? store.votes[proposal.id]

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZIPBadge(zipNumber: proposal.zipNumber ?? "ZIP-TBD")
                Spacer()
                if let choice {
                    let info = voteBadgeInfo(for: choice, proposal: proposal)
                    VoteBadgePill(label: info.label, color: info.color)
                }
            }

            Text(proposal.title)
                .zFont(.semiBold, size: 16, style: Design.Text.primary)
                .tracking(-0.256)
                .fixedSize(horizontal: false, vertical: true)

            if !proposal.description.isEmpty {
                Text(proposal.description)
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    .tracking(-0.224)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Design.Spacing._xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
        .shadow(color: Self.shadowSm, radius: 12, x: 0, y: 24)
        .shadow(color: Self.shadowSm, radius: 1.5, x: 0, y: 3)
        .shadow(color: Self.shadowSm, radius: 0.5, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            store.send(.proposalTapped(proposal.id))
        }
    }

    private static let shadowSm = Color(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0).opacity(0.04)
}

// MARK: - Bottom CTA

extension ProposalListView {
    @ViewBuilder
    func bottomCTA() -> some View {
        let status = store.batchSubmissionStatus

        switch status {
        case .idle:
            ctaButton()
        case .authorizing, .submitting, .completed, .failed:
            // In-flight / result states keep the existing batchFooter UI for now.
            // Will get its own redesign in a separate change.
            batchFooter()
        }
    }

    @ViewBuilder
    private func ctaButton() -> some View {
        let spec = ctaButtonSpec()
        ZashiButton(spec.label) {
            spec.action()
        }
        .disabled(spec.disabled)
    }

    private struct CTAButtonSpec {
        let label: String
        let action: () -> Void
        let disabled: Bool
    }

    private func ctaButtonSpec() -> CTAButtonSpec {
        switch mode {
        case .review:
            return CTAButtonSpec(
                label: "Confirm & Submit",
                action: { store.send(.submitAllDrafts) },
                disabled: false
            )

        case .voting:
            let proposals = store.votingRound.proposals
            let drafts = store.draftVotes
            let draftCount = drafts.count
            let total = proposals.count
            let firstUndrafted = proposals.first { drafts[$0.id] == nil }

            if total == 0 {
                return CTAButtonSpec(label: "Start Voting", action: {}, disabled: true)
            }

            if draftCount == 0 {
                let action: () -> Void = firstUndrafted.map { target in
                    { store.send(.proposalTapped(target.id)) }
                } ?? {}
                return CTAButtonSpec(label: "Start Voting", action: action, disabled: false)
            }

            if draftCount < total {
                let action: () -> Void = firstUndrafted.map { target in
                    { store.send(.proposalTapped(target.id)) }
                } ?? {}
                return CTAButtonSpec(label: "Continue Voting", action: action, disabled: false)
            }

            return CTAButtonSpec(
                label: "Review & Submit",
                action: { store.send(.navigateToReview) },
                disabled: false
            )
        }
    }
}

// MARK: - Batch Footer (legacy in-flight states)

extension ProposalListView {
    @ViewBuilder
    func batchFooter() -> some View {
        let status = store.batchSubmissionStatus

        switch status {
        case .idle:
            EmptyView()

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
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
            )

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
                            .fill(Design.Surfaces.bgTertiary.color(colorScheme))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Design.Text.primary.color(colorScheme))
                            .frame(width: geo.size.width * Double(currentIndex + 1) / Double(totalCount))
                            .animation(.easeInOut(duration: 0.3), value: currentIndex)
                    }
                }
                .frame(height: 3)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
            )

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

                ZashiButton("Done") {
                    store.send(.dismissBatchResults)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
            )

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
        }
    }
}
