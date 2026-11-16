#if os(macOS)
import SwiftUI

struct NotchWaveformView: View {
    let amplitude: Float  // 0…1

    private static let barFactors: [Float] = [0.55, 0.95, 0.75, 1.0, 0.65, 0.85]
    private static let baseHeight: CGFloat = 3
    private static let maxHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barFactors.count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: height(for: i))
                    .animation(.easeOut(duration: 0.12), value: amplitude)
            }
        }
        .frame(height: Self.maxHeight)
    }

    private func height(for index: Int) -> CGFloat {
        let factor = Self.barFactors[index]
        let scaled = CGFloat(min(1, max(0.05, amplitude * factor)))
        return Self.baseHeight + scaled * (Self.maxHeight - Self.baseHeight)
    }
}
#endif
