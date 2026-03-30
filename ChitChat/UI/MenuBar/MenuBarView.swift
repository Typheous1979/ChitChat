import SwiftUI
import ChitChatCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    var onQuitClicked: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            if let error = appState.currentError {
                errorBanner(error)
            }
            Divider()
            statusSection
            Divider()
            recentTranscriptionsSection
            Divider()
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("ChitChat")
                .font(.headline)
            Spacer()
            if appState.isRecording {
                recordingBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recordingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("Recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red.opacity(0.1), in: Capsule())
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isRecording {
                Text(appState.currentTranscription.isEmpty ? "Listening..." : appState.currentTranscription)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                    Text("Press \(appState.settingsManager.settings.hotkeyBinding.displayString) to start dictating")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !appState.allPermissionsGranted {
                permissionWarning
            }

            if !appState.isRecording {
                engineStatusLabel
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var engineStatusLabel: some View {
        let isWhisper = appState.settingsManager.settings.transcriptionEngine == .whisperCpp

        HStack(spacing: 6) {
            Image(systemName: isWhisper ? "cpu" : "cloud")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if isWhisper {
                Text("Whisper — \(appState.settingsManager.settings.whisperModel.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !appState.isTranscriptionReady {
                    Text("(not downloaded)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Deepgram")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var permissionWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text("Permissions required")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Recent Transcriptions

    private var recentTranscriptionsSection: some View {
        let maxItems = appState.settingsManager.settings.maxRecentTranscriptions
        let items = Array(appState.recentTranscriptions.prefix(maxItems))

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if !items.isEmpty {
                    Button("Clear All") {
                        appState.recentTranscriptions.removeAll()
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if items.isEmpty {
                Text("No recent transcriptions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else if items.count <= 10 {
                ForEach(items) { transcription in
                    TranscriptionRow(transcription: transcription)
                }
            } else {
                // First 10 visible, rest in scrollable area
                ForEach(items.prefix(10)) { transcription in
                    TranscriptionRow(transcription: transcription)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items.dropFirst(10)) { transcription in
                            TranscriptionRow(transcription: transcription)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            if message.contains("model") || message.contains("Settings") || message.contains("API") {
                Button("Settings") {
                    appState.currentError = nil
                    if let openSettings = NSApp.value(forKey: "openSettings") as? () -> Void {
                        openSettings()
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
            Button {
                appState.currentError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.red.opacity(0.1))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onQuitClicked) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Transcription Row

private struct TranscriptionRow: View {
    let transcription: RecentTranscription

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transcription.text)
                    .font(.callout)
                    .lineLimit(1)
                Text(Self.minuteAgo(transcription.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcription.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    static func minuteAgo(_ date: Date) -> String {
        let minutes = Int(-date.timeIntervalSinceNow / 60)
        if minutes < 1 { return "Just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours == 1 { return "1 hour ago" }
        if hours < 24 { return "\(hours) hours ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
