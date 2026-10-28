import SwiftUI
import SwitcherCore

struct ReorderableAccountRow<Content: View>: View {
    @ObservedObject var model: AppModel
    let account: AccountProfile
    var isEnabled = true
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 1
    @GestureState private var dragOffset: CGFloat = 0

    private var canReorder: Bool {
        isEnabled && !model.isMutating && !model.isAddingAccount && model.accounts.count > 1
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 32)
                .contentShape(Rectangle())
                .help(model.text("drag_to_reorder"))
                .accessibilityLabel(model.format("reorder_account", account.email ?? account.displayName))
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($dragOffset) { value, offset, _ in
                        if canReorder { offset = value.translation.height }
                    }
                    .onEnded { value in
                        guard canReorder,
                              let source = model.accounts.firstIndex(where: { $0.id == account.id }) else { return }
                        let steps = Int((value.translation.height / (height + spacing)).rounded())
                        let destination = min(max(source + steps, 0), model.accounts.count - 1)
                        guard destination != source else { return }
                        let targetID = model.accounts[destination].id
                        Task { await model.moveAccount(id: account.id, relativeTo: targetID, after: destination > source) }
                    })
                .opacity(canReorder ? 1 : 0.35)
            content
        }
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { height = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in height = value }
            }
        }
        .offset(y: dragOffset)
        .zIndex(dragOffset == 0 ? 0 : 1)
    }
}
