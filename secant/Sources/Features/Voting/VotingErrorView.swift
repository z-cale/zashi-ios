import SwiftUI
import ComposableArchitecture

struct VotingErrorView: View {
    let store: StoreOf<Voting>
    let errorMessage: String
    @State private var errorSheetPresented = true
    @State private var dismissFlowAfterSheetDismiss = false

    var body: some View {
        WithPerceptionTracking {
            VotingBlockingBackdrop(store: store)
                .votingSheet(
                    isPresented: errorBinding,
                    title: String(localizable: .coinVoteErrorTitle),
                    message: errorMessage,
                    primary: .init(title: String(localizable: .coinVoteCommonRetry), style: .primary) {
                        store.send(.initialize)
                    },
                    secondary: .init(title: String(localizable: .coinVoteCommonDismiss), style: .secondary) {
                        dismissSheetAndFlow()
                    },
                    onDismiss: dismissFlowIfNeeded
                )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorSheetPresented && isCurrentErrorScreen },
            set: { newValue in
                if !newValue && isCurrentErrorScreen {
                    dismissFlowAfterSheetDismiss = true
                }
                errorSheetPresented = newValue
            }
        )
    }

    private var isCurrentErrorScreen: Bool {
        if case .error = store.currentScreen { return true }
        return false
    }

    private func dismissSheetAndFlow() {
        dismissFlowAfterSheetDismiss = true
        errorSheetPresented = false
    }

    private func dismissFlowIfNeeded() {
        guard dismissFlowAfterSheetDismiss else { return }
        dismissFlowAfterSheetDismiss = false
        store.send(.dismissFlow)
    }
}

struct VotingConfigErrorView: View {
    let store: StoreOf<Voting>
    let errorMessage: String
    @State private var errorSheetPresented = true
    @State private var dismissFlowAfterSheetDismiss = false

    var body: some View {
        WithPerceptionTracking {
            VotingBlockingBackdrop(store: store)
                .votingSheet(
                    isPresented: errorBinding,
                    iconSystemName: "arrow.up.circle",
                    title: String(localizable: .coinVoteConfigErrorTitle),
                    message: errorMessage,
                    primary: .init(title: String(localizable: .coinVoteCommonDismiss), style: .primary) {
                        dismissSheetAndFlow()
                    },
                    onDismiss: dismissFlowIfNeeded
                )
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorSheetPresented && isCurrentErrorScreen },
            set: { newValue in
                if !newValue && isCurrentErrorScreen {
                    dismissFlowAfterSheetDismiss = true
                }
                errorSheetPresented = newValue
            }
        )
    }

    private var isCurrentErrorScreen: Bool {
        if case .configError = store.currentScreen { return true }
        return false
    }

    private func dismissSheetAndFlow() {
        dismissFlowAfterSheetDismiss = true
        errorSheetPresented = false
    }

    private func dismissFlowIfNeeded() {
        guard dismissFlowAfterSheetDismiss else { return }
        dismissFlowAfterSheetDismiss = false
        store.send(.dismissFlow)
    }
}
