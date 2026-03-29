import SwiftUI
import AVFoundation

struct PermissionsStepView: View {
    @Environment(AppState.self) private var appState
    @State private var timer: Timer?
    @State private var micStatus: PermissionStatus = .notDetermined
    @State private var axStatus: PermissionStatus = .denied

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Permissions")
                .font(.title)
                .fontWeight(.bold)

            Text("ChitChat needs a few permissions to work properly.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture your voice for transcription.",
                    status: micStatus,
                    action: requestMicrophone
                )

                permissionCard(
                    icon: "lock.shield",
                    title: "Accessibility",
                    description: "Required to detect text fields and type on your behalf.",
                    status: axStatus,
                    action: { PlatformCapabilities.openAccessibilitySettings() }
                )
            }
            .padding(.horizontal, 40)

            if micStatus == .granted && axStatus == .granted {
                Label("All permissions granted!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Spacer()
        }
        .onAppear {
            refreshStatus()
            startPolling()
        }
        .onDisappear { timer?.invalidate() }
    }

    private func permissionCard(icon: String, title: String, description: String, status: PermissionStatus, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 40)
                .foregroundStyle(status == .granted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    PermissionStatusBadge(status: status)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status != .granted {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                appState.isMicrophoneGranted = granted
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func refreshStatus() {
        micStatus = PlatformCapabilities.microphoneStatus
        axStatus = PlatformCapabilities.accessibilityStatus
        appState.isMicrophoneGranted = micStatus == .granted
        appState.isAccessibilityGranted = axStatus == .granted
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in refreshStatus() }
        }
    }
}
