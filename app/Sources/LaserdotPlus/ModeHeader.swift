import SwiftUI

/// One header for every mode that covers the files (Review, What Is This?,
/// Duplicates): its icon and title, where it is or how far along, its own
/// controls, and Done (Esc).
struct ModeHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let done: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            trailing()
            Button(L("review.done"), action: done)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
