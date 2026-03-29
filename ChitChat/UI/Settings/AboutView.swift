import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("ChitChat")
                .font(.title)
                .fontWeight(.bold)

            Text("Voice-to-Text Dictation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 6) {
                infoRow("macOS", value: PlatformCapabilities.osVersion)
                infoRow("Architecture", value: PlatformCapabilities.isAppleSilicon ? "Apple Silicon" : "Intel")
                infoRow("Microphone", badge: PlatformCapabilities.microphoneStatus)
                infoRow("Accessibility", badge: PlatformCapabilities.accessibilityStatus)
            }
            .padding(.horizontal, 60)

            Spacer()

            Text("Built with Deepgram and Whisper")
                .font(.caption2)
                .foregroundStyle(.quaternary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func infoRow(_ label: String, badge: PermissionStatus) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            PermissionStatusBadge(status: badge)
        }
    }
}
