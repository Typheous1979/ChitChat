import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
            }

            Text("ChitChat")
                .font(.title2)
                .fontWeight(.bold)

            Text("Voice-to-Text Dictation")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 4) {
                infoRow("macOS", value: PlatformCapabilities.osVersion)
                infoRow("Architecture", value: PlatformCapabilities.isAppleSilicon ? "Apple Silicon" : "Intel")
                infoRow("Microphone", badge: PlatformCapabilities.microphoneStatus)
                infoRow("Accessibility", badge: PlatformCapabilities.accessibilityStatus)
            }
            .padding(.horizontal, 60)

            Divider()
                .padding(.horizontal, 60)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/Typheous1979/ChitChat")!)
                Link("Report Issue", destination: URL(string: "https://github.com/Typheous1979/ChitChat/issues")!)
            }
            .font(.caption)

            Spacer()

            VStack(spacing: 2) {
                Text("Built with Deepgram and Whisper")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("whisper.cpp (MIT) via SwiftWhisper")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text("Copyright \u{00A9} 2026 Justin Kalicharan. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
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
