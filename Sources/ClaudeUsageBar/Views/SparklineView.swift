import SwiftUI

struct SparklineView: View {
    let records: [UsageHistoryRecord]
    let keyPath: KeyPath<UsageHistoryRecord, Int>
    let color: Color
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if records.count >= 2 {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height

                    ZStack(alignment: .bottom) {
                        fillPath(width: width, height: height)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.3), color.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        linePath(width: width, height: height)
                            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                Text("Collecting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func linePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let points = normalizedPoints(width: width, height: height)
            guard points.count >= 2 else { return }
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let points = normalizedPoints(width: width, height: height)
            guard points.count >= 2 else { return }
            path.move(to: CGPoint(x: points[0].x, y: height))
            path.addLine(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: points.last!.x, y: height))
            path.closeSubpath()
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard records.count >= 2 else { return [] }
        let maxIndex = CGFloat(records.count - 1)
        return records.enumerated().map { index, record in
            let x = (CGFloat(index) / maxIndex) * width
            let value = CGFloat(record[keyPath: keyPath])
            let y = height - (value / 100.0) * height
            return CGPoint(x: x, y: y)
        }
    }
}
