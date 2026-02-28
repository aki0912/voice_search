import SwiftUI
import Combine

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.modifier(LegacyOnChangeModifier(value: value, action: action))
        }
    }
}

private struct LegacyOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void

    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content.onReceive(Just(value)) { newValue in
            if let previousValue, previousValue != newValue {
                action(newValue)
            }
            previousValue = newValue
        }
    }
}
