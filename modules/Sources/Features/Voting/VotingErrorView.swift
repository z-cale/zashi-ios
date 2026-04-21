import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

struct VotingErrorView: View {
    @Environment(\.colorScheme)
    var colorScheme

    let store: StoreOf<Voting>
    let errorMessage: String

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Design.Utility.ErrorRed._500.color(colorScheme).opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(Design.Utility.ErrorRed._500.color(colorScheme))
                    }

                    // Title
                    Text("Something Went Wrong")
                        .zFont(.semiBold, size: 22, style: Design.Text.primary)

                    // Description (already mapped to a user-friendly message by VotingErrorMapper)
                    Text(errorMessage)
                        .zFont(.regular, size: 15, style: Design.Text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Retry + Dismiss buttons
                VStack(spacing: 12) {
                    ZashiButton("Retry") {
                        store.send(.initialize)
                    }

                    ZashiButton("Dismiss", type: .ghost) {
                        store.send(.dismissFlow)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Governance")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.screenBackground.color(colorScheme))
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
}

struct VotingConfigErrorView: View {
    @Environment(\.colorScheme)
    var colorScheme

    let store: StoreOf<Voting>
    let errorMessage: String

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Design.Utility.ErrorRed._500.color(colorScheme).opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(Design.Utility.ErrorRed._500.color(colorScheme))
                    }

                    Text("Wallet Update Required")
                        .zFont(.semiBold, size: 22, style: Design.Text.primary)

                    Text(errorMessage)
                        .zFont(.regular, size: 15, style: Design.Text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // "Retry" gives the user a self-recovery path: if the config was stale due to
                // a round transition the single lazy-refresh didn't catch (e.g. the publisher
                // updated the CDN after the first fetch), tapping Retry re-runs the full init
                // pipeline with a fresh config fetch.
                VStack(spacing: 12) {
                    ZashiButton("Retry") {
                        store.send(.retryConfigFetch)
                    }

                    ZashiButton("Dismiss", type: .ghost) {
                        store.send(.dismissFlow)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Governance")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.screenBackground.color(colorScheme))
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
}
