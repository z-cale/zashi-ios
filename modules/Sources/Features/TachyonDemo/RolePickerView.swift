import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Perspective Switch Screen

/// Shown between sender/recipient parts of a flow to indicate
/// which device we're now looking at.
struct PerspectiveSwitchView: View {
    let store: StoreOf<TachyonDemo>
    let perspective: TachyonDemo.State.Perspective

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: perspective.systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(perspectiveColor)

                Text(perspective.title)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text(perspective.subtitle)
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Continue") {
                    store.send(.proceedTapped)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .navigationBarBackButtonHidden(true)
        }
        .applyScreenBackground()
    }

    private var perspectiveColor: Color {
        switch perspective {
        case .sender: return .blue
        case .recipient: return .green
        case .recipientOffline: return .orange
        }
    }
}
