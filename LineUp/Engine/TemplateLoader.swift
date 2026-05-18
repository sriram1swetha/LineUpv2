import Foundation
import CoreGraphics

// MARK: - JSON-decodable template types

struct ArcDef: Codable {
    let cx: CGFloat
    let cy: CGFloat
    let r: CGFloat
}

struct WallDef: Codable {
    let x1: CGFloat
    let y1: CGFloat
    let x2: CGFloat
    let y2: CGFloat
}

struct ShapeTemplate: Codable {
    let name: String
    let emoji: String?
    let unitDots: [[CGFloat]]
    let connections: [[Int]]?
    let arcs: [ArcDef]?
    let walls: [WallDef]?
    let description: String?
    let connectionHints: [String]?
}

struct ShapeCatalog: Codable {
    let lineTemplates: [ShapeTemplate]
    let curveTemplates: [ShapeTemplate]
    let mazeTemplates: [ShapeTemplate]
    let iconLineTemplates: [ShapeTemplate]?
    let natureFoodTemplates: [ShapeTemplate]?
    let symbolTemplates: [ShapeTemplate]?
}

// MARK: - Loader

enum TemplateLoader {

    private static var _catalog: ShapeCatalog?

    static var catalog: ShapeCatalog {
        if let c = _catalog { return c }
        guard let url = Bundle.main.url(forResource: "shapes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(ShapeCatalog.self, from: data) else {
            print("TemplateLoader: shapes.json not found or invalid.")
            let empty = ShapeCatalog(lineTemplates: [], curveTemplates: [], mazeTemplates: [],
                                     iconLineTemplates: nil, natureFoodTemplates: nil, symbolTemplates: nil)
            _catalog = empty
            return empty
        }
        _catalog = c
        return c
    }

    static var lineTemplates: [ShapeTemplate]       { catalog.lineTemplates }
    static var curveTemplates: [ShapeTemplate]      { catalog.curveTemplates }
    static var mazeTemplates: [ShapeTemplate]       { catalog.mazeTemplates }
    static var iconLineTemplates: [ShapeTemplate]   { catalog.iconLineTemplates ?? [] }
    static var natureFoodTemplates: [ShapeTemplate] { catalog.natureFoodTemplates ?? [] }
    static var symbolTemplates: [ShapeTemplate]     { catalog.symbolTemplates ?? [] }

    // MARK: - Config builders

    static func buildLineConfig(template t: ShapeTemplate,
                                cx: CGFloat, cy: CGFloat,
                                scale: CGFloat) -> DotConfiguration {
        let dots = t.unitDots.map { CGPoint(x: cx + $0[0] * scale, y: cy + $0[1] * scale) }
        let conns: [(Int, Int)]
        if let c = t.connections { conns = c.map { ($0[0], $0[1]) } }
        else { conns = (0..<dots.count).map { ($0, ($0 + 1) % dots.count) } }
        let walls = buildWalls(from: t, cx: cx, cy: cy, scale: scale)
        return DotConfiguration(dots: dots, connections: conns, shapeName: t.name,
                                shapeEmoji: t.emoji, walls: walls)
    }

    static func buildCurveConfig(template t: ShapeTemplate,
                                 cx: CGFloat, cy: CGFloat,
                                 scale: CGFloat) -> DotConfiguration {
        let dots = t.unitDots.map { CGPoint(x: cx + $0[0] * scale, y: cy + $0[1] * scale) }
        let conns: [(Int, Int)]
        if let c = t.connections { conns = c.map { ($0[0], $0[1]) } }
        else { conns = (0..<dots.count).map { ($0, ($0 + 1) % dots.count) } }
        var perArcs: [(center: CGPoint, radius: CGFloat)?]? = nil
        if let arcs = t.arcs {
            perArcs = arcs.map { a in
                (center: CGPoint(x: cx + a.cx * scale, y: cy + a.cy * scale),
                 radius: a.r * scale)
            }
        }
        return DotConfiguration(dots: dots, connections: conns, shapeName: t.name,
                                perConnectionArcs: perArcs,
                                shapeEmoji: t.emoji,
                                shapeDescription: t.description,
                                connectionHints: t.connectionHints)
    }

    static func buildMazeConfig(template t: ShapeTemplate,
                                cx: CGFloat, cy: CGFloat,
                                scale: CGFloat) -> DotConfiguration {
        let dots = t.unitDots.map { CGPoint(x: cx + $0[0] * scale, y: cy + $0[1] * scale) }
        let conns: [(Int, Int)]
        if let c = t.connections { conns = c.map { ($0[0], $0[1]) } }
        else { conns = (0..<dots.count).map { ($0, ($0 + 1) % dots.count) } }
        let walls = buildWalls(from: t, cx: cx, cy: cy, scale: scale)
        return DotConfiguration(dots: dots, connections: conns, shapeName: t.name,
                                shapeEmoji: t.emoji,
                                shapeDescription: t.description, walls: walls)
    }

    private static func buildWalls(from t: ShapeTemplate,
                                   cx: CGFloat, cy: CGFloat,
                                   scale: CGFloat) -> [(CGPoint, CGPoint)]? {
        guard let defs = t.walls else { return nil }
        return defs.map { w in
            (CGPoint(x: cx + w.x1 * scale, y: cy + w.y1 * scale),
             CGPoint(x: cx + w.x2 * scale, y: cy + w.y2 * scale))
        }
    }

    // MARK: - Index-based convenience (called by LevelGenerator)

    /// Returns nil if the JSON catalog is empty (graceful fallback).
    static func lineShape(index: Int, cx: CGFloat, cy: CGFloat,
                          radius: CGFloat) -> DotConfiguration? {
        let ts = lineTemplates
        guard !ts.isEmpty else { return nil }
        let t = ts[((index % ts.count) + ts.count) % ts.count]
        return buildLineConfig(template: t, cx: cx, cy: cy, scale: radius)
    }

    static func curveShape(index: Int, cx: CGFloat, cy: CGFloat,
                           radius: CGFloat) -> DotConfiguration? {
        let ts = curveTemplates
        guard !ts.isEmpty else { return nil }
        let t = ts[((index % ts.count) + ts.count) % ts.count]
        return buildCurveConfig(template: t, cx: cx, cy: cy, scale: radius)
    }

    static func maze(index: Int, cx: CGFloat, cy: CGFloat,
                     radius: CGFloat) -> DotConfiguration? {
        let ts = mazeTemplates
        guard !ts.isEmpty else { return nil }
        let t = ts[((index % ts.count) + ts.count) % ts.count]
        return buildMazeConfig(template: t, cx: cx, cy: cy, scale: radius)
    }

    // MARK: - Name/count lookups (for game cards — no geometry needed)

    static func lineShapeName(index: Int) -> String {
        let ts = lineTemplates
        guard !ts.isEmpty else { return "Shape" }
        return ts[((index % ts.count) + ts.count) % ts.count].name
    }

    static func curveShapeName(index: Int) -> String {
        let ts = curveTemplates
        guard !ts.isEmpty else { return "Curve" }
        return ts[((index % ts.count) + ts.count) % ts.count].name
    }

    static func mazeName(index: Int) -> String {
        let ts = mazeTemplates
        guard !ts.isEmpty else { return "Maze" }
        return ts[((index % ts.count) + ts.count) % ts.count].name
    }

    static func connectionCount(template t: ShapeTemplate) -> Int {
        if let c = t.connections { return c.count }
        return t.unitDots.count   // closed loop = dot count edges
    }

    static func lineShapeConnectionCount(index: Int) -> Int {
        let ts = lineTemplates
        guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[((index % ts.count) + ts.count) % ts.count])
    }

    static func curveShapeConnectionCount(index: Int) -> Int {
        let ts = curveTemplates
        guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[((index % ts.count) + ts.count) % ts.count])
    }

    static func mazeConnectionCount(index: Int) -> Int {
        let ts = mazeTemplates
        guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[((index % ts.count) + ts.count) % ts.count])
    }

    // MARK: - Icon / Nature / Symbol level helpers

    private static func safeIndex(_ index: Int, in ts: [ShapeTemplate]) -> Int {
        ((index % ts.count) + ts.count) % ts.count
    }

    static func iconShape(index: Int, cx: CGFloat, cy: CGFloat,
                          radius: CGFloat) -> DotConfiguration? {
        let ts = iconLineTemplates
        guard !ts.isEmpty else { return nil }
        return buildLineConfig(template: ts[safeIndex(index, in: ts)], cx: cx, cy: cy, scale: radius)
    }

    static func natureFoodShape(index: Int, cx: CGFloat, cy: CGFloat,
                                radius: CGFloat) -> DotConfiguration? {
        let ts = natureFoodTemplates
        guard !ts.isEmpty else { return nil }
        return buildLineConfig(template: ts[safeIndex(index, in: ts)], cx: cx, cy: cy, scale: radius)
    }

    static func symbolShape(index: Int, cx: CGFloat, cy: CGFloat,
                            radius: CGFloat) -> DotConfiguration? {
        let ts = symbolTemplates
        guard !ts.isEmpty else { return nil }
        return buildLineConfig(template: ts[safeIndex(index, in: ts)], cx: cx, cy: cy, scale: radius)
    }

    static func iconShapeName(index: Int) -> String {
        let ts = iconLineTemplates; guard !ts.isEmpty else { return "Object" }
        return ts[safeIndex(index, in: ts)].name
    }

    static func natureFoodShapeName(index: Int) -> String {
        let ts = natureFoodTemplates; guard !ts.isEmpty else { return "Nature" }
        return ts[safeIndex(index, in: ts)].name
    }

    static func symbolShapeName(index: Int) -> String {
        let ts = symbolTemplates; guard !ts.isEmpty else { return "Symbol" }
        return ts[safeIndex(index, in: ts)].name
    }

    static func iconShapeConnectionCount(index: Int) -> Int {
        let ts = iconLineTemplates; guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[safeIndex(index, in: ts)])
    }

    static func natureFoodConnectionCount(index: Int) -> Int {
        let ts = natureFoodTemplates; guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[safeIndex(index, in: ts)])
    }

    static func symbolConnectionCount(index: Int) -> Int {
        let ts = symbolTemplates; guard !ts.isEmpty else { return 1 }
        return connectionCount(template: ts[safeIndex(index, in: ts)])
    }
}
