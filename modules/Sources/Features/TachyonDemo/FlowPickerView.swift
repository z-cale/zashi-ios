import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

struct FlowPickerView: View {
    let store: StoreOf<TachyonDemo>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                demoBanner

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(TachyonDemo.State.Flow.allCases, id: \.self) { flow in
                            flowCard(flow)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        store.send(.dismissFlow)
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Tachyon")
                        .font(.headline)
                }
            }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "flask.fill")
                .foregroundStyle(.orange)
            Text("Prototype — all crypto is mocked")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private func flowCard(_ flow: TachyonDemo.State.Flow) -> some View {
        Button {
            store.send(.flowSelected(flow))
        } label: {
            HStack(spacing: 16) {
                Image(systemName: flow.systemImage)
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(flow.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
