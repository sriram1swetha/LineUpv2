import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { p in
                p.move(to: CGPoint(x: 72, y: 172)); p.addLine(to: CGPoint(x: 228, y: 172))
            }
            .stroke(Color(hex: "f5a623").opacity(0.7),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
            lineSegment(from: CGPoint(x: 72, y: 172), to: CGPoint(x: 150, y: 118),
                        color: Color(hex: "e94560"), width: 9)
            lineSegment(from: CGPoint(x: 150, y: 118), to: CGPoint(x: 228, y: 172),
                        color: Color(hex: "e94560"), width: 9)
            dot(at: CGPoint(x: 72, y: 172), color: Color(hex: "e94560"), radius: 16)
            dot(at: CGPoint(x: 150, y: 118), color: .white, radius: 13)
            dot(at: CGPoint(x: 228, y: 172), color: Color(hex: "f5a623"), radius: 16)
            VStack {
                Spacer()
                Text("ConnectDaDots")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 66))
    }

    @ViewBuilder
    private func lineSegment(from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat) -> some View {
        Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    @ViewBuilder
    private func dot(at pos: CGPoint, color: Color, radius: CGFloat) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.3)).frame(width: radius * 2.6, height: radius * 2.6)
            Circle().fill(color).frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
        }
        .position(pos)
    }
}

#Preview { AppIconView().padding(40).background(Color.gray.opacity(0.2)) }
