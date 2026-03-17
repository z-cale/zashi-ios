import SwiftUI
import Generated
import UIComponents

// MARK: - Demo Data

private struct DemoQuestion: Identifiable {
    let id: String
    let title: String
    let description: String
    let variant: Variant

    enum Variant {
        /// All options shown flat, single selection
        case flat([String])
        /// Binary first, sub-options revealed on trigger
        case conditional(primary: [String], triggerIndex: Int, followUp: FollowUp)
        /// Yes-variants grouped under a "Yes" header, No stands alone
        case grouped(yesLabel: String, yesOptions: [String], noLabel: String)
    }

    struct FollowUp {
        let prompt: String
        let options: [String]
    }
}

/// Each "scenario" has the same question shown in all 3 variant styles.
private struct DemoScenario {
    let label: String
    let questions: [DemoQuestion] // one per variant tab
}

private let scenarios: [DemoScenario] = [
    DemoScenario(
        label: "Sprout Deprecation",
        questions: [
            // Conditional
            DemoQuestion(
                id: "sprout-cond",
                title: "Sprout pool v4 transaction deprecation",
                description: "When should the protocol disable v4 transactions, making Sprout funds inaccessible? If you choose a fixed date, a follow-up question determines the timeline.",
                variant: .conditional(
                    primary: [
                        "Immediately upon NU7 activation date",
                        "At a fixed date following poll conclusion",
                        "When quantum threat is imminent, and the Orchard pool transitions to recovery only",
                    ],
                    triggerIndex: 1,
                    followUp: .init(
                        prompt: "When following poll conclusion?",
                        options: [
                            "One year following poll conclusion date",
                            "Two years following poll conclusion date",
                        ]
                    )
                )
            ),
            // Flat
            DemoQuestion(
                id: "sprout-flat",
                title: "Sprout pool v4 transaction deprecation",
                description: "When should the protocol disable v4 transactions, making Sprout funds inaccessible?",
                variant: .flat([
                    "Immediately upon NU7 activation date",
                    "At a fixed date following poll conclusion \u{2014} one year",
                    "At a fixed date following poll conclusion \u{2014} two years",
                    "When quantum threat is imminent, and the Orchard pool transitions to recovery only",
                ])
            ),
            // Grouped
            DemoQuestion(
                id: "sprout-grp",
                title: "Sprout pool v4 transaction deprecation",
                description: "When should the protocol disable v4 transactions, making Sprout funds inaccessible?",
                variant: .grouped(
                    yesLabel: "Yes, disable v4 transactions",
                    yesOptions: [
                        "Immediately upon NU7 activation date",
                        "One year following poll conclusion date",
                        "Two years following poll conclusion date",
                    ],
                    noLabel: "When quantum threat is imminent, and the Orchard pool transitions to recovery only"
                )
            ),
        ]
    ),
    DemoScenario(
        label: "Memo Bundles",
        questions: [
            // Conditional
            DemoQuestion(
                id: "memo-cond",
                title: "Memo bundles for Orchard in NU7",
                description: "Do you support activation of memo bundles for Orchard in NU7?",
                variant: .conditional(
                    primary: [
                        "Yes, with sizing variant selected below",
                        "No",
                    ],
                    triggerIndex: 0,
                    followUp: .init(
                        prompt: "Which memo size limit?",
                        options: [
                            "16 KiB memo size limit (as specified)",
                            "10 KiB memo size limit",
                            "Temporary 1 KiB limit (not sufficient for authenticated reply address)",
                            "A different size (re-poll)",
                        ]
                    )
                )
            ),
            // Flat
            DemoQuestion(
                id: "memo-flat",
                title: "Memo bundles for Orchard in NU7",
                description: "Do you support activation of memo bundles for Orchard in NU7?",
                variant: .flat([
                    "Yes with the specified 16 KiB memo size limit",
                    "Yes with a 10 KiB memo size limit",
                    "Yes with a temporary 1 KiB memo size limit",
                    "No",
                ])
            ),
            // Grouped
            DemoQuestion(
                id: "memo-grp",
                title: "Memo bundles for Orchard in NU7",
                description: "Do you support activation of memo bundles for Orchard in NU7?",
                variant: .grouped(
                    yesLabel: "Yes, activate memo bundles",
                    yesOptions: [
                        "16 KiB memo size limit (as specified)",
                        "10 KiB memo size limit",
                        "Temporary 1 KiB limit (not sufficient for authenticated reply address)",
                        "A different size (re-poll)",
                    ],
                    noLabel: "No"
                )
            ),
        ]
    ),
    DemoScenario(
        label: "Fee Burn",
        questions: [
            // Conditional
            DemoQuestion(
                id: "fee-cond",
                title: "Transaction fee burn requirement",
                description: "With regard to the NSM, do you support requiring a portion of transaction fees to be removed from circulation?",
                variant: .conditional(
                    primary: [
                        "Yes, require a portion of fees to be burned",
                        "No, I support voluntary removal only",
                        "I do not support any part of the NSM",
                    ],
                    triggerIndex: 0,
                    followUp: .init(
                        prompt: "What percentage of transaction fees?",
                        options: [
                            "60% of transaction fees",
                            "30% of transaction fees",
                        ]
                    )
                )
            ),
            // Flat
            DemoQuestion(
                id: "fee-flat",
                title: "Transaction fee burn requirement",
                description: "With regard to the NSM, do you support requiring a portion of transaction fees to be removed from circulation?",
                variant: .flat([
                    "Yes, 60% of transaction fees",
                    "Yes, 30% of transaction fees",
                    "No, I support voluntary removal only",
                    "I do not support any part of the NSM",
                ])
            ),
            // Grouped
            DemoQuestion(
                id: "fee-grp",
                title: "Transaction fee burn requirement",
                description: "With regard to the NSM, do you support requiring a portion of transaction fees to be removed from circulation?",
                variant: .grouped(
                    yesLabel: "Yes, require fee burn",
                    yesOptions: [
                        "60% of transaction fees",
                        "30% of transaction fees",
                    ],
                    noLabel: "I do not support any part of the NSM"
                )
            ),
        ]
    ),
]

// MARK: - Color helpers

private func optionColor(for index: Int, total: Int) -> Color {
    let palette: [Color] = [.green, .blue, .purple, .orange, .teal, .pink, .indigo]
    if index == total - 1 && total > 2 { return .red }
    return palette[index % palette.count]
}

private func optionIcon(for index: Int, total: Int) -> String {
    if total == 2 { return index == 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill" }
    return "\(index + 1).circle.fill"
}

private let followUpPalette: [Color] = [.blue, .cyan, .teal, .indigo]

// MARK: - Root Demo View

struct MultiOptionDemoView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var variantTab = 0
    @State private var scenarioIndex = 0

    private let variantNames = ["Conditional", "All Options", "Grouped"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Variant picker
                Picker("Variant", selection: $variantTab) {
                    ForEach(Array(variantNames.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 0)

                // Full-screen question view
                let question = scenarios[scenarioIndex].questions[variantTab]
                DemoQuestionDetailView(
                    question: question,
                    positionLabel: "\(scenarioIndex + 1) of \(scenarios.count)",
                    colorScheme: colorScheme
                )
                .id(question.id)
            }
            .navigationTitle("Multi-Option Vote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation { scenarioIndex = max(0, scenarioIndex - 1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .disabled(scenarioIndex == 0)

                        Button {
                            withAnimation { scenarioIndex = min(scenarios.count - 1, scenarioIndex + 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .disabled(scenarioIndex == scenarios.count - 1)
                    }
                }
            }
        }
    }
}

// MARK: - Full-Screen Question Detail (matches ProposalDetailView)

private struct DemoQuestionDetailView: View {
    let question: DemoQuestion
    let positionLabel: String
    let colorScheme: ColorScheme

    @State private var primarySelection: Int?
    @State private var followUpSelection: Int?
    @State private var pendingConfirm = false
    @State private var confirmed = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.title)
                            .zFont(.semiBold, size: 22, style: Design.Text.primary)

                        Text(question.description)
                            .zFont(.regular, size: 15, style: Design.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    variantBadge()

                    Spacer().frame(height: 8)

                    // Vote section
                    voteSection()

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            // Confirmation overlay
            if pendingConfirm {
                confirmationOverlay()
            }
        }
    }

    @ViewBuilder
    private func variantBadge() -> some View {
        let label: String = {
            switch question.variant {
            case .conditional: return "Conditional reveal"
            case .flat: return "All options visible"
            case .grouped: return "Grouped yes / no"
            }
        }()

        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Vote Section

    @ViewBuilder
    private func voteSection() -> some View {
        if confirmed {
            confirmedBanner()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    primarySelection = nil
                    followUpSelection = nil
                    confirmed = false
                    pendingConfirm = false
                }
            } label: {
                Text("Reset")
                    .zFont(.medium, size: 13, style: Design.Text.secondary)
                    .padding(.top, 4)
            }
        } else {
            VStack(spacing: 12) {
                switch question.variant {
                case .flat(let options):
                    flatSection(options)
                case .conditional(let primary, let triggerIndex, let followUp):
                    conditionalSection(primary: primary, triggerIndex: triggerIndex, followUp: followUp)
                case .grouped(let yesLabel, let yesOptions, let noLabel):
                    groupedSection(yesLabel: yesLabel, yesOptions: yesOptions, noLabel: noLabel)
                }
            }
        }
    }

    // MARK: - Flat

    @ViewBuilder
    private func flatSection(_ options: [String]) -> some View {
        ForEach(Array(options.enumerated()), id: \.offset) { index, label in
            voteButton(
                title: label,
                icon: optionIcon(for: index, total: options.count),
                color: optionColor(for: index, total: options.count),
                isSelected: primarySelection == index
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    primarySelection = index
                    pendingConfirm = true
                }
            }
        }
    }

    // MARK: - Conditional

    @ViewBuilder
    private func conditionalSection(primary: [String], triggerIndex: Int, followUp: DemoQuestion.FollowUp) -> some View {
        ForEach(Array(primary.enumerated()), id: \.offset) { index, label in
            voteButton(
                title: label,
                icon: optionIcon(for: index, total: primary.count),
                color: optionColor(for: index, total: primary.count),
                isSelected: primarySelection == index
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    primarySelection = index
                    followUpSelection = nil
                    if index != triggerIndex {
                        pendingConfirm = true
                    }
                }
            }
        }

        if primarySelection == triggerIndex {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 3, height: 20)

                    Text(followUp.prompt)
                        .zFont(.medium, size: 14, style: Design.Text.secondary)
                }
                .padding(.top, 4)

                ForEach(Array(followUp.options.enumerated()), id: \.offset) { index, label in
                    followUpButton(
                        title: label,
                        index: index,
                        total: followUp.options.count,
                        isSelected: followUpSelection == index
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            followUpSelection = index
                            pendingConfirm = true
                        }
                    }
                }
            }
            .padding(.leading, 16)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)),
                removal: .opacity
            ))
        }
    }

    // MARK: - Grouped (Yes with sub-options / No)

    @ViewBuilder
    private func groupedSection(yesLabel: String, yesOptions: [String], noLabel: String) -> some View {
        // "Yes" header button
        let yesSelected = primarySelection != nil && primarySelection! < yesOptions.count
        let yesColor = Color.green

        Button {
            impactFeedback.impactOccurred()
            // If tapping Yes header and no sub-option yet, just expand
            if !yesSelected {
                withAnimation(.easeInOut(duration: 0.25)) {
                    primarySelection = -1 // sentinel: yes expanded but no sub-option
                }
            }
        } label: {
            HStack {
                Image(systemName: "hand.thumbsup.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(yesLabel)
                        .fontWeight(.semibold)
                    if !yesSelected && primarySelection != -1 {
                        Text("\(yesOptions.count) options")
                            .font(.system(size: 12))
                            .opacity(0.7)
                    }
                }
                Spacer()
                if yesSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
                if !yesSelected {
                    Image(systemName: primarySelection == -1 ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .foregroundStyle(yesSelected ? .white : yesColor)
            .background(yesSelected ? yesColor : yesColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(yesColor.opacity(0.3), lineWidth: yesSelected ? 0 : 1)
            )
        }

        // Yes sub-options (indented)
        let showSubOptions = primarySelection == -1 || yesSelected
        if showSubOptions {
            VStack(spacing: 8) {
                ForEach(Array(yesOptions.enumerated()), id: \.offset) { index, label in
                    followUpButton(
                        title: label,
                        index: index,
                        total: yesOptions.count,
                        isSelected: primarySelection == index
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            primarySelection = index
                            pendingConfirm = true
                        }
                    }
                }
            }
            .padding(.leading, 24)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)),
                removal: .opacity
            ))
        }

        // "No" button
        let noIndex = yesOptions.count
        let noSelected = primarySelection == noIndex
        let noColor = Color.red

        voteButton(
            title: noLabel,
            icon: "hand.thumbsdown.fill",
            color: noColor,
            isSelected: noSelected
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                primarySelection = noIndex
                pendingConfirm = true
            }
        }
    }

    // MARK: - Shared Button Components

    @ViewBuilder
    private func voteButton(
        title: String,
        icon: String,
        color: Color,
        isSelected: Bool,
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
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? .white : color)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.3), lineWidth: isSelected ? 0 : 1)
            )
        }
    }

    @ViewBuilder
    private func followUpButton(
        title: String,
        index: Int,
        total: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let color = followUpPalette[index % followUpPalette.count]

        Button {
            impactFeedback.impactOccurred()
            action()
        } label: {
            HStack {
                Image(systemName: "\(index + 1).circle")
                    .font(.system(size: 14))
                Text(title)
                    .fontWeight(.medium)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .foregroundStyle(isSelected ? .white : color)
            .background(isSelected ? color : color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.25), lineWidth: isSelected ? 0 : 1)
            )
        }
    }

    // MARK: - Confirmed Banner

    @ViewBuilder
    private func confirmedBanner() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(resolvedColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vote recorded")
                    .zFont(.semiBold, size: 15, style: Design.Text.primary)
                ForEach(summaryLines, id: \.self) { line in
                    Text(line)
                        .zFont(.medium, size: 13, style: Design.Text.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(resolvedColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(resolvedColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Confirmation Overlay (matches real voting UI)

    @ViewBuilder
    private func confirmationOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pendingConfirm = false
                    }
                }

            VStack(spacing: 0) {
                // Icon
                ZStack {
                    Circle()
                        .fill(resolvedColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28))
                        .foregroundStyle(resolvedColor)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)

                Text("Confirm your vote")
                    .zFont(.semiBold, size: 20, style: Design.Text.primary)
                    .padding(.bottom, 6)

                // Choice summary
                VStack(spacing: 2) {
                    ForEach(summaryLines, id: \.self) { line in
                        Text(line)
                            .zFont(.semiBold, size: 15, style: Design.Text.primary)
                            .foregroundStyle(resolvedColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                Text("This is final. Your vote will be\npublished and cannot be changed.")
                    .zFont(.medium, size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)

                VStack(spacing: 10) {
                    Button {
                        impactFeedback.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            confirmed = true
                            pendingConfirm = false
                        }
                    } label: {
                        Text("Confirm")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(resolvedColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            pendingConfirm = false
                        }
                    } label: {
                        Text("Go Back")
                            .zFont(.medium, size: 15, style: Design.Text.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Design.Surfaces.bgPrimary.color(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }

    // MARK: - Helpers

    private var resolvedColor: Color {
        guard let idx = primarySelection else { return .green }
        switch question.variant {
        case .flat(let options):
            return optionColor(for: idx, total: options.count)
        case .conditional(let primary, _, _):
            return optionColor(for: idx, total: primary.count)
        case .grouped(_, let yesOptions, _):
            if idx < yesOptions.count || idx == -1 { return .green }
            return .red
        }
    }

    private var summaryLines: [String] {
        guard let idx = primarySelection else { return [] }
        var lines: [String] = []

        switch question.variant {
        case .flat(let options):
            if idx < options.count { lines.append(options[idx]) }

        case .conditional(let primary, let triggerIndex, let followUp):
            if idx < primary.count { lines.append(primary[idx]) }
            if idx == triggerIndex, let fuIdx = followUpSelection, fuIdx < followUp.options.count {
                lines.append(followUp.options[fuIdx])
            }

        case .grouped(_, let yesOptions, let noLabel):
            if idx >= 0 && idx < yesOptions.count {
                lines.append(yesOptions[idx])
            } else if idx == yesOptions.count {
                lines.append(noLabel)
            }
        }
        return lines
    }
}

// MARK: - Preview

#Preview("Multi-Option Demo") {
    MultiOptionDemoView()
}
