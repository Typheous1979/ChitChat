import SwiftUI

/// Shared state for the overlay, updated from AppDelegate without replacing the view hierarchy.
@Observable
@MainActor
final class OverlayState {
    var text: String = ""
    var isFinal: Bool = false
}

/// The SwiftUI content displayed in the transcription overlay window.
struct TranscriptionOverlayView: View {
    @Environment(OverlayState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            // Recording indicator
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(state.isFinal ? 0.4 : 1.0)

            // Transcription text
            if state.text.isEmpty {
                Text("Listening...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(state.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }
}
