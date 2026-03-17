import ComposableArchitecture
import CoreGraphics
import Foundation

@Reducer
public struct TachyonDemo {
    @Dependency(\.mainQueue) var mainQueue

    private enum CancelID {
        case simulatedDelay
        case qrGeneration
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            // Top level
            case flowPicker
            case rolePicker(Flow)

            // Flow 1: Payment Request
            case prRecipientCreate
            case prRecipientShowQR
            case prSenderScan
            case prSenderConfirm
            case prSenderProcessing
            case prSenderDone
            case prRecipientReceived

            // Flow 2: URI-Encapsulated Payment / Local Cash
            case lcSenderEnterAmount
            case lcSenderShowPayment
            case lcRecipientClaim
            case lcRecipientClaiming
            case lcRecipientDone

            // Flow 3: Public Payment
            case ppRecipientRegister
            case ppRecipientRegistering
            case ppRecipientShowURL
            case ppSenderScan
            case ppSenderEnterAmount
            case ppSenderConfirm
            case ppSenderProcessing
            case ppSenderDone
            case ppRecipientCheckRelay
            case ppRecipientChecking
            case ppRecipientPaymentsArrived
        }

        public enum Flow: Equatable, CaseIterable {
            case paymentRequest
            case uriEncapsulatedPayment
            case publicPayment

            public var title: String {
                switch self {
                case .paymentRequest: return "Payment Request"
                case .uriEncapsulatedPayment: return "Send Payment"
                case .publicPayment: return "Public Payment"
                }
            }

            public var description: String {
                switch self {
                case .paymentRequest:
                    return "Request a payment by sharing a QR code"
                case .uriEncapsulatedPayment:
                    return "Send as a link or Local Cash QR"
                case .publicPayment:
                    return "Accept payments while offline via relay"
                }
            }

            public var systemImage: String {
                switch self {
                case .paymentRequest: return "qrcode"
                case .uriEncapsulatedPayment: return "paperplane.fill"
                case .publicPayment: return "antenna.radiowaves.left.and.right"
                }
            }
        }

        public enum Role: Equatable {
            case recipient
            case sender

            public var title: String {
                switch self {
                case .recipient: return "I'm the Recipient"
                case .sender: return "I'm the Sender"
                }
            }
        }

        public var screenStack: [Screen] = [.flowPicker]
        public var selectedFlow: Flow?

        // Amount input
        public var amount: String = ""

        // QR
        public var qrCodeImage: CGImage?
        public var qrContent: String = ""

        // Share
        public var isSharePresented: Bool = false

        // Relay
        public var relayURL: String = ""

        // Mock received payments
        public var receivedPayments: [MockPayment] = []

        public static let initial = State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: Equatable {
        // Navigation
        case dismissFlow
        case goBack
        case flowSelected(State.Flow)
        case roleSelected(State.Role)

        // Amount
        case amountChanged(String)

        // Proceed through screens
        case proceedTapped
        case simulateReceived

        // QR
        case generateQRCode(String)
        case qrCodeGenerated(CGImage?)

        // Share
        case sharePayment
        case shareFinished

        // Delays
        case simulatedDelayCompleted

        // Public Payment specific
        case registerWithRelay
        case checkRelay

        // Reset
        case backToFlowPicker
    }

    // MARK: - Reducer

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .dismissFlow:
                state.screenStack = [.flowPicker]
                state.reset()
                return .cancel(id: CancelID.simulatedDelay)

            case .goBack:
                if state.screenStack.count > 1 {
                    state.screenStack.removeLast()
                }
                return .none

            case .backToFlowPicker:
                state.screenStack = [.flowPicker]
                state.reset()
                return .none

            case let .flowSelected(flow):
                state.selectedFlow = flow
                state.screenStack.append(.rolePicker(flow))
                return .none

            case let .roleSelected(role):
                guard let flow = state.selectedFlow else { return .none }
                let screen = firstScreen(for: flow, role: role)
                state.screenStack.append(screen)
                return .none

            // MARK: Amount

            case let .amountChanged(text):
                state.amount = text
                return .none

            // MARK: QR

            case let .generateQRCode(content):
                state.qrContent = content
                // QR generation will be wired in views phase
                return .none

            case let .qrCodeGenerated(image):
                state.qrCodeImage = image
                return .none

            // MARK: Share

            case .sharePayment:
                state.isSharePresented = true
                return .none

            case .shareFinished:
                state.isSharePresented = false
                return .none

            // MARK: Flow navigation

            case .proceedTapped:
                return handleProceed(&state)

            case .simulateReceived:
                return handleSimulateReceived(&state)

            case .simulatedDelayCompleted:
                return handleDelayCompleted(&state)

            case .registerWithRelay:
                state.screenStack.append(.ppRecipientRegistering)
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(3))
                    await send(.simulatedDelayCompleted)
                }
                .cancellable(id: CancelID.simulatedDelay)

            case .checkRelay:
                state.screenStack.append(.ppRecipientChecking)
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(3))
                    await send(.simulatedDelayCompleted)
                }
                .cancellable(id: CancelID.simulatedDelay)
            }
        }
    }

    // MARK: - Helpers

    private func firstScreen(for flow: State.Flow, role: State.Role) -> State.Screen {
        switch (flow, role) {
        case (.paymentRequest, .recipient): return .prRecipientCreate
        case (.paymentRequest, .sender): return .prSenderScan
        case (.uriEncapsulatedPayment, .recipient): return .lcRecipientClaim
        case (.uriEncapsulatedPayment, .sender): return .lcSenderEnterAmount
        case (.publicPayment, .recipient): return .ppRecipientRegister
        case (.publicPayment, .sender): return .ppSenderScan
        }
    }

    private func handleProceed(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {
        // Flow 1: Payment Request
        case .prRecipientCreate:
            let amount = state.amount.isEmpty ? "1.0" : state.amount
            state.qrContent = TachyonURI.paymentRequest(
                pk: MockData.recipientKey.hex,
                amount: amount
            )
            state.screenStack.append(.prRecipientShowQR)
            return .none

        case .prSenderScan:
            state.amount = "1.0"
            state.screenStack.append(.prSenderConfirm)
            return .none

        case .prSenderConfirm:
            state.screenStack.append(.prSenderProcessing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // Flow 2: Local Cash
        case .lcSenderEnterAmount:
            let amount = state.amount.isEmpty ? "1.0" : state.amount
            state.qrContent = TachyonURI.encapsulatedPayment(noteHex: MockData.mockNoteHex)
            state.screenStack.append(.lcSenderShowPayment)
            _ = amount
            return .none

        case .lcRecipientClaim:
            state.screenStack.append(.lcRecipientClaiming)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // Flow 3: Public Payment
        case .ppSenderScan:
            state.screenStack.append(.ppSenderEnterAmount)
            return .none

        case .ppSenderEnterAmount:
            state.screenStack.append(.ppSenderConfirm)
            return .none

        case .ppSenderConfirm:
            state.screenStack.append(.ppSenderProcessing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(2))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        default:
            return .none
        }
    }

    private func handleSimulateReceived(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {
        case .prRecipientShowQR:
            state.screenStack.append(.prRecipientReceived)
            return .none
        default:
            return .none
        }
    }

    private func handleDelayCompleted(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {
        case .prSenderProcessing:
            state.screenStack.append(.prSenderDone)
            return .none

        case .lcRecipientClaiming:
            state.screenStack.append(.lcRecipientDone)
            return .none

        case .ppRecipientRegistering:
            state.relayURL = TachyonURI.relayURL(relayId: MockData.relayId)
            state.qrContent = state.relayURL
            state.screenStack.append(.ppRecipientShowURL)
            return .none

        case .ppSenderProcessing:
            state.screenStack.append(.ppSenderDone)
            return .none

        case .ppRecipientChecking:
            state.receivedPayments = MockData.mockReceivedPayments()
            state.screenStack.append(.ppRecipientPaymentsArrived)
            return .none

        default:
            return .none
        }
    }
}

// MARK: - State Reset

extension TachyonDemo.State {
    mutating func reset() {
        selectedFlow = nil
        amount = ""
        qrCodeImage = nil
        qrContent = ""
        isSharePresented = false
        relayURL = ""
        receivedPayments = []
    }
}
