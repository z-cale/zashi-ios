import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

struct FlowPickerView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                DemoBanner()

                RoleLegend()
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(TachyonDemo.State.Flow.allCases, id: \.self) { flow in
                            flowCard(flow)
                        }
                    }
                    .padding(.top, 16)
                }
                .screenHorizontalPadding()
            }
            .zashiBack(hidden: true)
            .screenTitle("Tachyon")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.send(.dismissFlow)
                    } label: {
                        Image(systemName: "xmark")
                            .zImage(size: 16, style: Design.Text.primary)
                    }
                }
            }
        }
        .applyScreenBackground()
    }

    private func flowCard(_ flow: TachyonDemo.State.Flow) -> some View {
        Button {
            store.send(.flowSelected(flow))
        } label: {
            HStack(spacing: 16) {
                Image(systemName: flow.systemImage)
                    .zImage(size: 24, style: Design.Text.primary)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.title)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)

                    Text(flow.description)
                        .zFont(size: 14, style: Design.Text.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .zImage(size: 12, style: Design.Text.quaternary)
            }
            .padding(16)
            .background { RoundedRectangle(cornerRadius: Design.Radius._xl).fill().zForegroundColor(Design.Surfaces.bgSecondary) }
        }
        .buttonStyle(.plain)
    }
}
