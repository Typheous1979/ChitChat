import SwiftUI

/// Real-time audio waveform visualization.
/// Feed new amplitude samples to update the display.
struct WaveformView: View {
    let samples: [Float]
    var barColor: Color = .accentColor
    var backgroundColor: Color = .secondary.opacity(0.1)
    var barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(1, (geometry.size.width - CGFloat(samples.count - 1) * barSpacing) / CGFloat(max(samples.count, 1)))
            let midY = geometry.size.height / 2

            Canvas { context, size in
                // Background
                let bgPath = RoundedRectangle(cornerRadius: 6).path(in: CGRect(origin: .zero, size: size))
                context.fill(bgPath, with: .color(backgroundColor))

                // Waveform bars
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * (barWidth + barSpacing)
                    let amplitude = CGFloat(min(abs(sample), 1.0))
                    let barHeight = max(2, amplitude * geometry.size.height * 0.9)

                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    let barPath = RoundedRectangle(cornerRadius: barWidth / 2).path(in: rect)
                    context.fill(barPath, with: .color(barColor.opacity(0.3 + Double(amplitude) * 0.7)))
                }
            }
        }
    }
}

/// A waveform that manages its own sample buffer, suitable for real-time audio.
struct LiveWaveformView: View {
    @State private var samples: [Float] = []
    let maxSamples: Int
    let audioLevel: Float

    init(audioLevel: Float, maxSamples: Int = 60) {
        self.audioLevel = audioLevel
        self.maxSamples = maxSamples
    }

    var body: some View {
        WaveformView(samples: samples)
            .onChange(of: audioLevel) { _, newLevel in
                samples.append(newLevel)
                if samples.count > maxSamples {
                    samples.removeFirst()
                }
            }
    }
}
