import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { p in p.move(to: CGPoint(x: 72, y: 172)); p.addLine(to: CGPoint(x: 228, y: 172)) }
                .stroke(Color(hex: "f5a623").opacity(0.7), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            segment(CGPoint(x: 72, y: 172), CGPoint(x: 150, y: 118), Color(hex: "e94560"), 9)
            segment(CGPoint(x: 150, y: 118), CGPoint(x: 228, y: 172), Color(hex: "e94560"), 9)
            dot(CGPoint(x: 72, y: 172), Color(hex: "e94560"), 16)
            dot(CGPoint(x: 150, y: 118), .white, 13)
            dot(CGPoint(x: 228, y: 172), Color(hex: "f5a623"), 16)
            VStack { Spacer()
                Text("LineUp").font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 3, y: 2).padding(.bottom, 28)
            }
        }
        .frame(width: 300, height: 300).clipShape(RoundedRectangle(cornerRadius: 66))
    }
    @ViewBuilder private func segment(_ a: CGPoint, _ b: CGPoint, _ c: Color, _ w: CGFloat) -> some View {
        Path { p in p.move(to: a); p.addLine(to: b) }.stroke(c, style: StrokeStyle(lineWidth: w, lineCap: .round))
    }
    @ViewBuilder private func dot(_ pos: CGPoint, _ color: Color, _ r: CGFloat) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.3)).frame(width: r*2.6, height: r*2.6)
            Circle().fill(color).frame(width: r*2, height: r*2).overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
        }.position(pos)
    }
}

#Preview { AppIconView().padding(40).background(Color.gray.opacity(0.2)) }
