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
            case flowPicker

            // Perspective switch
            case switchTo(Perspective)

            // Flow 1: Payment Request
            // Recipient creates → shows QR → switch → Sender scans → confirms → sends → switch → Recipient sees received
            case prRecipientCreate
            case prRecipientShowQR
            case prSenderConfirm
            case prSenderProcessing
            case prRecipientReceived

            // Flow 2: URI-Encapsulated Payment / Local Cash
            // Sender enters amount → shows QR/share → switch → Recipient claims → done
            case lcSenderEnterAmount
            case lcSenderShowPayment
            case lcRecipientClaim
            case lcRecipientClaiming
            case lcRecipientDone

            // Flow 3: Public Payment
            // Recipient registers → gets URL → goes offline → switch → Sender scans → amount → confirms → sends → switch → Recipient checks relay → payments
            case ppRecipientRegister
            case ppRecipientRegistering
            case ppRecipientShowURL
            case ppSenderEnterAmount
            case ppSenderConfirm
            case ppSenderProcessing
            case ppRecipientCheckRelay
            case ppRecipientChecking
            case ppRecipientPaymentsArrived

            public var role: Role? {
                switch self {
                case .flowPicker, .switchTo:
                    return nil
                case .prRecipientCreate, .prRecipientShowQR, .prRecipientReceived,
                     .lcRecipientClaim, .lcRecipientClaiming, .lcRecipientDone,
                     .ppRecipientRegister, .ppRecipientRegistering, .ppRecipientShowURL,
                     .ppRecipientCheckRelay, .ppRecipientChecking, .ppRecipientPaymentsArrived:
                    return .recipient
                case .prSenderConfirm, .prSenderProcessing,
                     .lcSenderEnterAmount, .lcSenderShowPayment,
                     .ppSenderEnterAmount, .ppSenderConfirm, .ppSenderProcessing:
                    return .sender
                }
            }
        }

        public enum Perspective: Equatable {
            case sender
            case recipient
            case recipientOffline

            public var title: String {
                switch self {
                case .sender: return "Sender's Device"
                case .recipient: return "Recipient's Device"
                case .recipientOffline: return "Recipient Goes Offline"
                }
            }

            public var subtitle: String {
                switch self {
                case .sender: return "Now viewing the sender's perspective"
                case .recipient: return "Now viewing the recipient's perspective"
                case .recipientOffline: return "The recipient puts their phone away. Time passes..."
                }
            }

            public var systemImage: String {
                switch self {
                case .sender: return "arrow.up.circle.fill"
                case .recipient: return "arrow.down.circle.fill"
                case .recipientOffline: return "moon.zzz.fill"
                }
            }
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

        // MARK: - Screen Role

        public enum Role: Equatable {
            case recipient
            case sender

            public var label: String {
                switch self {
                case .recipient: return "Recipient's Device"
                case .sender: return "Sender's Device"
                }
            }
        }

        public var screenStack: [Screen] = [.flowPicker]
        public var selectedFlow: Flow?

        public var activeRole: Role? {
            screenStack.last?.role
        }

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

        // Amount
        case amountChanged(String)

        // Proceed through screens
        case proceedTapped

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
                switch flow {
                case .paymentRequest:
                    state.screenStack.append(.prRecipientCreate)
                case .uriEncapsulatedPayment:
                    state.screenStack.append(.lcSenderEnterAmount)
                case .publicPayment:
                    state.screenStack.append(.ppRecipientRegister)
                }
                return .none

            // MARK: Amount

            case let .amountChanged(text):
                state.amount = text
                return .none

            // MARK: QR

            case let .generateQRCode(content):
                state.qrContent = content
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

    private func handleProceed(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {

        // MARK: Flow 1 — Payment Request
        // Recipient creates → QR → [switch to sender] → confirm → processing → [switch to recipient] → received

        case .prRecipientCreate:
            let amount = state.amount.isEmpty ? "1.0" : state.amount
            state.qrContent = TachyonURI.paymentRequest(
                pk: MockData.recipientKey.hex,
                amount: amount
            )
            state.screenStack.append(.prRecipientShowQR)
            return .none

        case .prRecipientShowQR:
            // Recipient showed QR → switch to sender who "scanned" it
            state.screenStack.append(.switchTo(.sender))
            return .none

        case .switchTo(.sender) where state.selectedFlow == .paymentRequest:
            state.screenStack.append(.prSenderConfirm)
            return .none

        case .prSenderConfirm:
            state.screenStack.append(.prSenderProcessing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // MARK: Flow 2 — Local Cash / URI Payment
        // Sender enters amount → shows QR/share → [switch to recipient] → claim → done

        case .lcSenderEnterAmount:
            state.qrContent = TachyonURI.encapsulatedPayment(noteHex: MockData.mockNoteHex)
            state.screenStack.append(.lcSenderShowPayment)
            return .none

        case .lcSenderShowPayment:
            state.screenStack.append(.switchTo(.recipient))
            return .none

        case .switchTo(.recipient) where state.selectedFlow == .paymentRequest:
            state.screenStack.append(.prRecipientReceived)
            return .none

        case .switchTo(.recipient) where state.selectedFlow == .uriEncapsulatedPayment:
            state.screenStack.append(.lcRecipientClaim)
            return .none

        case .lcRecipientClaim:
            state.screenStack.append(.lcRecipientClaiming)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // MARK: Flow 3 — Public Payment
        // Recipient registers → URL → [goes offline] → [switch to sender] → amount → confirm → processing → [switch to recipient] → check → payments

        case .ppRecipientShowURL:
            state.screenStack.append(.switchTo(.recipientOffline))
            return .none

        case .switchTo(.recipientOffline):
            state.screenStack.append(.switchTo(.sender))
            return .none

        case .switchTo(.sender) where state.selectedFlow == .publicPayment:
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

        // switchTo(.recipient) for public payment — after sender done
        case .switchTo(.recipient) where state.selectedFlow == .publicPayment:
            state.screenStack.append(.ppRecipientCheckRelay)
            return .none

        default:
            return .none
        }
    }

    private func handleDelayCompleted(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {
        case .prSenderProcessing:
            // Sender done → switch back to recipient
            state.screenStack.append(.switchTo(.recipient))
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
            // Sender done → switch to recipient coming back online
            state.screenStack.append(.switchTo(.recipient))
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
