import SwiftUI

struct AudioLevelMeter: View {
    let level: Float
    var barCount: Int = 20
    var activeColor: Color = .green
    var warningColor: Color = .yellow
    var peakColor: Color = .red

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let threshold = Float(index) / Float(barCount)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: index))
                        .opacity(level >= threshold ? 1.0 : 0.15)
                }
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        let ratio = Float(index) / Float(barCount)
        if ratio > 0.85 {
            return peakColor
        } else if ratio > 0.65 {
            return warningColor
        }
        return activeColor
    }
}
