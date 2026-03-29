import SwiftUI
import ChitChatCore

struct EnvironmentTestView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var phase: EnvironmentTestPhase?
    @State private var report: AudioEnvironmentReport?
    @State private var isRunning = false
    @State private var countdown: Int = 5
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Environment Test")
                .font(.title2.bold())

            if let report {
                resultView(report)
            } else if isRunning {
                runningView
            } else {
                readyView
            }

            Spacer()

            HStack {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)

                if report != nil {
                    Button("Re-test") {
                        report = nil
                        startTest()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
    }

    // MARK: - Ready State

    private var readyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("This test measures your audio environment in two phases:")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("Phase 1: Stay quiet for 5 seconds (measures background noise)", systemImage: "1.circle.fill")
                    .font(.callout)
                Label("Phase 2: Read a sentence aloud for 5 seconds (measures voice level)", systemImage: "2.circle.fill")
                    .font(.callout)
            }
            .padding()

            Button("Start Test") { startTest() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Running State

    private var runningView: some View {
        VStack(spacing: 16) {
            switch phase {
            case .measuringNoise:
                Image(systemName: "ear")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Phase 1 of 2: Measuring Background Noise")
                    .font(.headline)

                Text("Stay quiet \u{2014} measuring background noise (\(countdown)s remaining)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(5 - countdown), total: 5.0)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

            case .measuringSpeech:
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Phase 2 of 2: Measuring Your Voice")
                    .font(.headline)

                Text("Read the text below aloud (\(countdown)s remaining)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("\"The quick brown fox jumps over the lazy dog near the river bank.\"")
                    .font(.callout.italic())
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                ProgressView(value: Double(5 - countdown), total: 5.0)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

            default:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Processing...")
            }

            AudioLevelMeter(level: appState.currentAudioLevel)
                .frame(height: 16)
                .padding(.horizontal, 40)

            LiveWaveformView(audioLevel: appState.currentAudioLevel, maxSamples: 80)
                .frame(height: 50)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Result

    private func resultView(_ report: AudioEnvironmentReport) -> some View {
        VStack(spacing: 16) {
            // Grade badge
            resultBadge(report.recommendation)

            // Metrics
            VStack(spacing: 8) {
                metricRow("Noise Floor", value: "\(Int(report.noiseFloorDb)) dB", quality: report.noiseFloorDb < -40 ? .good : report.noiseFloorDb < -25 ? .fair : .poor)
                metricRow("Voice Level", value: "\(Int(report.speechLevelDb)) dB", quality: report.speechLevelDb > -30 ? .good : report.speechLevelDb > -40 ? .fair : .poor)
                metricRow("Signal-to-Noise", value: "\(Int(report.signalToNoiseRatio)) dB", quality: report.signalToNoiseRatio > 30 ? .good : report.signalToNoiseRatio > 15 ? .fair : .poor)
                if report.clippingDetected {
                    metricRow("Clipping", value: "Detected", quality: .poor)
                }
            }
            .padding()
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))

            // Suggestions
            if !report.recommendation.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggestions:")
                        .font(.subheadline.bold())
                    ForEach(report.recommendation.suggestions, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func resultBadge(_ recommendation: EnvironmentRecommendation) -> some View {
        VStack(spacing: 4) {
            let (color, icon) = badgeStyle(recommendation)
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(color)
            Text(recommendation.label)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(recommendation.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func badgeStyle(_ rec: EnvironmentRecommendation) -> (Color, String) {
        switch rec {
        case .excellent: return (.green, "checkmark.seal.fill")
        case .good: return (.blue, "hand.thumbsup.fill")
        case .fair: return (.yellow, "exclamationmark.triangle.fill")
        case .poor: return (.red, "xmark.octagon.fill")
        }
    }

    private enum MetricQuality { case good, fair, poor }

    private func metricRow(_ label: String, value: String, quality: MetricQuality) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(quality == .good ? .green : quality == .fair ? .yellow : .red)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.callout.monospacedDigit())
            }
        }
    }

    // MARK: - Test Execution

    private func startTest() {
        isRunning = true
        phase = nil
        report = nil
        countdown = 5

        Task {
            await appState.startLevelMonitoring()

            do {
                let audioStream = try await appState.services.audioCaptureService.startCapture(sampleRate: 16000, channels: 1)

                let analyzer = AudioLevelAnalyzer()
                let result = await analyzer.runEnvironmentTest(
                    audioStream: audioStream,
                    silenceDuration: 5.0,
                    speechDuration: 5.0,
                    onPhaseChange: { newPhase in
                        Task { @MainActor in
                            self.phase = newPhase
                            switch newPhase {
                            case .measuringNoise:
                                self.startCountdown()
                            case .measuringSpeech:
                                self.countdown = 5
                            case .complete:
                                self.countdownTask?.cancel()
                            }
                        }
                    }
                )

                await appState.services.audioCaptureService.stopCapture()
                await appState.stopLevelMonitoring()

                report = result
                isRunning = false
            } catch {
                isRunning = false
                countdownTask?.cancel()
                await appState.stopLevelMonitoring()
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 5
        countdownTask = Task { @MainActor in
            while countdown > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { countdown -= 1 }
            }
        }
    }
}
