import SwiftUI

/// Stateless white renderer for a GlyphModel. Scales to its frame.
struct GlyphView: View {
    let model: GlyphModel
    let lineWidth: CGFloat

    init(model: GlyphModel, lineWidth: CGFloat = 1.6) {
        self.model = model
        self.lineWidth = lineWidth
    }

    var body: some View {
        Canvas { context, size in
            GlyphView.draw(model: model, lineWidth: lineWidth, context: &context, size: size)
        }
    }

    private static func draw(model: GlyphModel, lineWidth: CGFloat, context: inout GraphicsContext, size: CGSize) {
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height / 2
        let radius: CGFloat = min(size.width, size.height) / 2 * 0.8

        var mapped: [CGPoint] = []
        for p in model.points {
            mapped.append(CGPoint(x: cx + p.x * radius, y: cy + p.y * radius))
        }

        var path = Path()
        for edge in model.edges {
            if edge.a < mapped.count && edge.b < mapped.count {
                path.move(to: mapped[edge.a])
                path.addLine(to: mapped[edge.b])
            }
        }
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        context.stroke(path, with: .color(Color.white.opacity(0.9)), style: style)

        let dotR: CGFloat = lineWidth * 1.6
        for pt in mapped {
            let rect = CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR * 2, height: dotR * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white))
        }

        if model.hasCenterDot {
            let cr: CGFloat = lineWidth * 1.3
            let rect = CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.85)))
        }
    }
}
