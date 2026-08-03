import SpriteKit
import SwiftUI

@MainActor
final class LoadScene: SKScene {
    private let logicalSize = CGSize(width: 960, height: 540)
    private let emitter = CGPoint(x: 424, y: 294)
    private var visual = LoadVisualState(
        state: "quiet", label: "QUIET", score: 0, constrained: false,
        activity: 0, parallel: 0, tempo: 0.2, travelMs: 4_800,
        clusterCount: 0, taskDensity: 0, pressure: 0,
        queueDepth: 0, heat: 0
    )
    private var particles: [SKSpriteNode] = []
    private var queueNodes: [SKSpriteNode] = []
    private var heatNodes: [SKSpriteNode] = []
    private var screenBars: [SKSpriteNode] = []
    private var startTime: TimeInterval?
    private var reduceMotion = false

    override init() {
        super.init(size: logicalSize)
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = reduceMotion ? 15 : 30
        buildGrid()
        buildWorkstation()
        buildFlow()
    }

    func apply(_ next: LoadVisualState, reduceMotion: Bool) {
        visual = next
        self.reduceMotion = reduceMotion
        view?.preferredFramesPerSecond = reduceMotion ? 15 : 30
        updatePalette()
    }

    override func update(_ currentTime: TimeInterval) {
        if startTime == nil { startTime = currentTime }
        let elapsed = max(0, currentTime - (startTime ?? currentTime))
        animateScreen(elapsed)
        animateFlow(elapsed)
        animateQueue(elapsed)
        animateHeat(elapsed)
    }

    private func buildGrid() {
        let grid = SKNode()
        grid.zPosition = -20
        for x in stride(from: 0, through: Int(logicalSize.width), by: 42) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.22),
                size: CGSize(width: 1, height: logicalSize.height)
            )
            line.position = CGPoint(x: CGFloat(x), y: logicalSize.height / 2)
            grid.addChild(line)
        }
        for y in stride(from: 0, through: Int(logicalSize.height), by: 42) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.22),
                size: CGSize(width: logicalSize.width, height: 1)
            )
            line.position = CGPoint(x: logicalSize.width / 2, y: CGFloat(y))
            grid.addChild(line)
        }
        addChild(grid)

        let floor = SKSpriteNode(
            color: UIColor(red: 0.15, green: 0.34, blue: 0.40, alpha: 0.32),
            size: CGSize(width: logicalSize.width - 32, height: 2)
        )
        floor.position = CGPoint(x: logicalSize.width / 2, y: 62)
        floor.zPosition = -10
        addChild(floor)
    }

    private func buildWorkstation() {
        let backing = SKShapeNode(rectOf: CGSize(width: 340, height: 290), cornerRadius: 2)
        backing.position = CGPoint(x: 206, y: 274)
        backing.fillColor = UIColor(red: 0.035, green: 0.055, blue: 0.064, alpha: 0.82)
        backing.strokeColor = UIColor(red: 0.18, green: 0.32, blue: 0.36, alpha: 0.45)
        backing.lineWidth = 2
        backing.zPosition = -5
        addChild(backing)

        let texture = SKTexture(imageNamed: "operator-workbench.webp")
        texture.filteringMode = .nearest
        let artwork = SKSpriteNode(texture: texture)
        artwork.size = CGSize(width: 430, height: 430)
        artwork.position = CGPoint(x: 210, y: 274)
        artwork.zPosition = 2
        addChild(artwork)

        let screen = SKShapeNode(rectOf: CGSize(width: 96, height: 74), cornerRadius: 1)
        screen.position = CGPoint(x: 305, y: 354)
        screen.fillColor = UIColor(red: 0.025, green: 0.085, blue: 0.09, alpha: 0.78)
        screen.strokeColor = UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.55)
        screen.lineWidth = 2
        screen.zPosition = 5
        addChild(screen)

        for index in 0..<7 {
            let bar = SKSpriteNode(
                color: index.isMultiple(of: 3)
                    ? UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.85)
                    : UIColor(red: 0.22, green: 0.85, blue: 0.57, alpha: 0.76),
                size: CGSize(width: CGFloat(22 + (index * 13) % 58), height: 4)
            )
            bar.anchorPoint = CGPoint(x: 0, y: 0.5)
            bar.position = CGPoint(x: 266, y: 378 - CGFloat(index * 9))
            bar.zPosition = 6
            screenBars.append(bar)
            addChild(bar)
        }

        let port = SKShapeNode(rectOf: CGSize(width: 20, height: 20), cornerRadius: 1)
        port.position = emitter
        port.fillColor = UIColor(red: 0.04, green: 0.1, blue: 0.11, alpha: 1)
        port.strokeColor = UIColor(red: 0.22, green: 0.85, blue: 0.57, alpha: 1)
        port.lineWidth = 3
        port.name = "emitter-port"
        port.zPosition = 10
        addChild(port)
    }

    private func buildFlow() {
        for index in 0..<220 {
            let node = SKSpriteNode(
                color: UIColor(red: 0.22, green: 0.85, blue: 0.57, alpha: 1),
                size: CGSize(width: index.isMultiple(of: 11) ? 15 : 7, height: 5)
            )
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.zPosition = 8
            node.isHidden = true
            node.name = "flow-\(index)"
            particles.append(node)
            addChild(node)
        }

        for index in 0..<16 {
            let node = SKSpriteNode(
                color: UIColor(red: 1, green: 0.71, blue: 0.30, alpha: 1),
                size: CGSize(width: index.isMultiple(of: 4) ? 10 : 6, height: 6)
            )
            node.zPosition = 9
            node.isHidden = true
            queueNodes.append(node)
            addChild(node)
        }

        for _ in 0..<5 {
            let node = SKSpriteNode(
                color: UIColor(red: 1, green: 0.71, blue: 0.30, alpha: 1),
                size: CGSize(width: 7, height: 16)
            )
            node.zPosition = 12
            node.isHidden = true
            heatNodes.append(node)
            addChild(node)
        }
    }

    private func animateScreen(_ elapsed: TimeInterval) {
        let speed = reduceMotion ? 0.28 : max(0.28, visual.tempo)
        for (index, bar) in screenBars.enumerated() {
            let pulse = 0.58 + 0.42 * sin(elapsed * speed * 2.2 + Double(index))
            bar.alpha = 0.32 + CGFloat(max(0.08, visual.activity)) * CGFloat(pulse) * 0.68
            bar.xScale = 0.62 + CGFloat(pulse) * 0.38
        }
        childNode(withName: "emitter-port")?.alpha = 0.62 + CGFloat(sin(elapsed * speed * 3) * 0.18)
    }

    private func animateFlow(_ elapsed: TimeInterval) {
        let count = visual.clusterCount == 0
            ? 0
            : min(particles.count, Int(28 + visual.taskDensity * 140 + visual.parallel * 44))
        let flowCount = max(1, visual.clusterCount)
        let spread = 56 + visual.activity * 190
        let speedScale = reduceMotion ? 0.28 : 1

        for (index, node) in particles.enumerated() {
            guard index < count else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let duration = max(0.76, visual.travelMs / 1_000) * (0.82 + Double(index % 7) * 0.055)
            let seed = noise(Double(index) * 8.173 + 1.7)
            let phase = fmod(elapsed * speedScale / duration + seed + Double(index) / Double(max(count, 1)), 1)
            let progress = phase * (1.08 - phase * 0.08)
            let band = index % flowCount
            let bandOffset = Double(band) - Double(flowCount - 1) / 2
            let fan = (noise(Double(index) + 2.4) - 0.5) * spread * (0.18 + progress * 0.68)
            let wave = sin(elapsed * (2.4 + Double(index % 5) * 0.21) + Double(index)) * (3 + visual.activity * 10)
            node.position = CGPoint(
                x: emitter.x + CGFloat(progress) * (logicalSize.width - emitter.x + 24),
                y: emitter.y + CGFloat(bandOffset * spread * 0.16 + fan + wave)
            )
            let envelope = min(1, phase / 0.055, (1 - phase) / 0.1)
            node.alpha = CGFloat(max(0, envelope) * (0.48 + visual.activity * 0.48))
            node.xScale = CGFloat(0.8 + visual.tempo * 0.42)

            if visual.pressure > 0.28 && progress > 0.38 {
                node.color = visual.pressure > 0.74 && progress > 0.58
                    ? UIColor(AmbientTheme.red)
                    : UIColor(AmbientTheme.amber)
            } else if index.isMultiple(of: 5) {
                node.color = UIColor(AmbientTheme.blue)
            } else {
                node.color = UIColor(AmbientTheme.green)
            }
        }
    }

    private func animateQueue(_ elapsed: TimeInterval) {
        let count = visual.queueDepth <= 0.05
            ? 0
            : min(queueNodes.count, Int(3 + visual.queueDepth * 13))
        for (index, node) in queueNodes.enumerated() {
            guard index < count else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let column = index % 6
            let row = index % 5
            let wobble = sin(elapsed * 4 + Double(index)) * (1 + visual.pressure * 5)
            node.position = CGPoint(
                x: emitter.x - CGFloat(24 + column * 14),
                y: emitter.y + CGFloat((row - 2) * 15) + CGFloat(wobble)
            )
            node.alpha = 0.28 + CGFloat(index % 3) * 0.14
            node.color = visual.pressure > 0.74 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
        }
    }

    private func animateHeat(_ elapsed: TimeInterval) {
        for (index, node) in heatNodes.enumerated() {
            node.isHidden = visual.heat <= 0.05
            guard !node.isHidden else { continue }
            node.position = CGPoint(
                x: 354 + CGFloat(index * 11),
                y: 314 + CGFloat(index % 2) * 12 + CGFloat(sin(elapsed * 3 + Double(index)) * 4)
            )
            node.alpha = 0.16 + CGFloat(visual.heat) * 0.56
            node.color = visual.pressure > 0.7 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
        }
    }

    private func updatePalette() {
        let color = UIColor(AmbientTheme.statusColor(visual.state))
        childNode(withName: "emitter-port").flatMap { $0 as? SKShapeNode }?.strokeColor = color
    }

    private func noise(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

struct LoadSceneView: View {
    let visual: LoadVisualState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = LoadScene()

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .background(AmbientTheme.background)
            .onAppear {
                scene.isPaused = false
                scene.apply(visual, reduceMotion: reduceMotion)
            }
            .onDisappear { scene.isPaused = true }
            .onChange(of: visual) { _, next in
                scene.apply(next, reduceMotion: reduceMotion)
            }
            .onChange(of: reduceMotion) { _, next in
                scene.apply(visual, reduceMotion: next)
            }
            .accessibilityLabel(
                String(
                    localized: "\(visual.label) aggregate Codex workload animation",
                    comment: "VoiceOver description for the aggregate Load animation."
                )
            )
    }
}

@MainActor
final class FleetLoadScene: SKScene {
    private struct NodeSurface {
        let container: SKNode
        let card: SKShapeNode
        let statusDot: SKShapeNode
        let name: SKLabelNode
        let detail: SKLabelNode
        let path: SKShapeNode
        let particles: [SKSpriteNode]
    }

    private let logicalSize = CGSize(width: 960, height: 540)
    private let corePoint = CGPoint(x: 480, y: 270)
    private let slotPositions = [
        CGPoint(x: 166, y: 405),
        CGPoint(x: 480, y: 434),
        CGPoint(x: 794, y: 405),
        CGPoint(x: 166, y: 135),
        CGPoint(x: 480, y: 106),
        CGPoint(x: 794, y: 135),
    ]
    private var presentation = FleetLoadPresentation(status: .unavailable())
    private var surfaces: [NodeSurface] = []
    private var coreRings: [SKShapeNode] = []
    private var startTime: TimeInterval?
    private var reduceMotion = false

    override init() {
        super.init(size: logicalSize)
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = reduceMotion ? 15 : 30
        buildGrid()
        buildCore()
        buildNodeSurfaces()
        updateSurfaces()
    }

    func apply(_ next: FleetLoadPresentation, reduceMotion: Bool) {
        presentation = next
        self.reduceMotion = reduceMotion
        view?.preferredFramesPerSecond = reduceMotion ? 15 : 30
        updateSurfaces()
    }

    override func update(_ currentTime: TimeInterval) {
        if startTime == nil { startTime = currentTime }
        let elapsed = max(0, currentTime - (startTime ?? currentTime))
        animateCore(elapsed)
        animateFlows(elapsed)
    }

    private func buildGrid() {
        let grid = SKNode()
        grid.zPosition = -30
        for x in stride(from: 0, through: Int(logicalSize.width), by: 40) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.18),
                size: CGSize(width: 1, height: logicalSize.height)
            )
            line.position = CGPoint(x: CGFloat(x), y: logicalSize.height / 2)
            grid.addChild(line)
        }
        for y in stride(from: 0, through: Int(logicalSize.height), by: 40) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.18),
                size: CGSize(width: logicalSize.width, height: 1)
            )
            line.position = CGPoint(x: logicalSize.width / 2, y: CGFloat(y))
            grid.addChild(line)
        }
        addChild(grid)
    }

    private func buildCore() {
        for radius in [88.0, 66.0, 43.0] {
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.position = corePoint
            ring.fillColor = radius == 43 ? UIColor(red: 0.03, green: 0.11, blue: 0.12, alpha: 0.95) : .clear
            ring.strokeColor = radius == 88
                ? UIColor(AmbientTheme.blue).withAlphaComponent(0.22)
                : UIColor(AmbientTheme.green).withAlphaComponent(0.58)
            ring.lineWidth = radius == 43 ? 3 : 2
            ring.zPosition = radius == 43 ? 4 : 1
            coreRings.append(ring)
            addChild(ring)
        }

        let icon = SKLabelNode(fontNamed: "Menlo-Bold")
        icon.text = "OPL"
        icon.fontSize = 21
        icon.fontColor = UIColor(AmbientTheme.green)
        icon.verticalAlignmentMode = .center
        icon.horizontalAlignmentMode = .center
        icon.position = CGPoint(x: corePoint.x, y: corePoint.y + 5)
        icon.zPosition = 7
        addChild(icon)

        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = "FLEET"
        label.fontSize = 10
        label.fontColor = UIColor(AmbientTheme.muted)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: corePoint.x, y: corePoint.y - 17)
        label.zPosition = 7
        addChild(label)
    }

    private func buildNodeSurfaces() {
        for (index, position) in slotPositions.enumerated() {
            let path = SKShapeNode()
            path.strokeColor = UIColor(AmbientTheme.line)
            path.lineWidth = 2
            path.zPosition = -2
            addChild(path)

            let container = SKNode()
            container.position = position
            container.zPosition = 8
            addChild(container)

            let card = SKShapeNode(rectOf: CGSize(width: 170, height: 78), cornerRadius: 5)
            card.fillColor = UIColor(red: 0.035, green: 0.055, blue: 0.064, alpha: 0.94)
            card.strokeColor = UIColor(AmbientTheme.line)
            card.lineWidth = 2
            container.addChild(card)

            let statusDot = SKShapeNode(circleOfRadius: 5)
            statusDot.position = CGPoint(x: -67, y: 20)
            statusDot.fillColor = UIColor(AmbientTheme.muted)
            statusDot.strokeColor = .clear
            statusDot.zPosition = 2
            container.addChild(statusDot)

            let name = SKLabelNode(fontNamed: "Menlo-Bold")
            name.fontSize = 15
            name.fontColor = .white
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -56, y: 20)
            name.zPosition = 2
            container.addChild(name)

            let detail = SKLabelNode(fontNamed: "Menlo")
            detail.fontSize = 11
            detail.fontColor = UIColor(AmbientTheme.muted)
            detail.horizontalAlignmentMode = .left
            detail.verticalAlignmentMode = .center
            detail.position = CGPoint(x: -68, y: -16)
            detail.zPosition = 2
            container.addChild(detail)

            var particles: [SKSpriteNode] = []
            for particleIndex in 0..<18 {
                let particle = SKSpriteNode(
                    color: particleIndex.isMultiple(of: 5)
                        ? UIColor(AmbientTheme.blue)
                        : UIColor(AmbientTheme.green),
                    size: CGSize(width: particleIndex.isMultiple(of: 7) ? 12 : 7, height: 4)
                )
                particle.zPosition = 3
                particle.isHidden = true
                particles.append(particle)
                addChild(particle)
            }

            surfaces.append(
                NodeSurface(
                    container: container,
                    card: card,
                    statusDot: statusDot,
                    name: name,
                    detail: detail,
                    path: path,
                    particles: particles
                )
            )
            updatePath(path, from: position, slotIndex: index)
        }
    }

    private func updatePath(_ node: SKShapeNode, from point: CGPoint, slotIndex: Int) {
        let path = CGMutablePath()
        path.move(to: point)
        let bend = CGPoint(
            x: (point.x + corePoint.x) / 2 + CGFloat(slotIndex.isMultiple(of: 2) ? 22 : -22),
            y: (point.y + corePoint.y) / 2 + CGFloat(slotIndex < 3 ? -12 : 12)
        )
        path.addQuadCurve(to: corePoint, control: bend)
        node.path = path
    }

    private func updateSurfaces() {
        let stateColor = UIColor(AmbientTheme.statusColor(presentation.visual.state))
        coreRings.last?.strokeColor = stateColor
        for (index, surface) in surfaces.enumerated() {
            guard index < presentation.nodes.count else {
                surface.container.isHidden = true
                surface.path.isHidden = true
                surface.particles.forEach { $0.isHidden = true }
                continue
            }
            let node = presentation.nodes[index]
            surface.container.isHidden = false
            surface.path.isHidden = false
            surface.name.text = displayName(node.name)
            surface.name.fontSize = node.name.count > 16 ? 11 : node.name.count > 12 ? 13 : 15
            surface.detail.text = node.status == "live"
                ? "\(MetricFormat.tps(node.tps)) TPS  ·  \(MetricFormat.integer(node.sessions)) ACTIVE"
                : node.status.uppercased()
            let color = nodeColor(node)
            surface.statusDot.fillColor = color
            surface.card.strokeColor = color.withAlphaComponent(node.status == "live" ? 0.68 : 0.32)
            surface.path.strokeColor = color.withAlphaComponent(node.isWorking ? 0.38 : 0.16)
            surface.name.fontColor = node.status == "live" ? .white : UIColor(AmbientTheme.muted)
            surface.detail.fontColor = node.isWorking ? color : UIColor(AmbientTheme.muted)
        }
    }

    private func animateCore(_ elapsed: TimeInterval) {
        let speed = reduceMotion ? 0.32 : max(0.45, presentation.visual.tempo)
        for (index, ring) in coreRings.enumerated() {
            let pulse = 0.5 + 0.5 * sin(elapsed * speed * (1.1 + Double(index) * 0.22) + Double(index))
            ring.alpha = 0.42 + CGFloat(pulse) * 0.48
            if index < 2 {
                let scale = 0.98 + CGFloat(pulse) * 0.045
                ring.setScale(scale)
            }
        }
    }

    private func animateFlows(_ elapsed: TimeInterval) {
        for (surfaceIndex, surface) in surfaces.enumerated() {
            guard surfaceIndex < presentation.nodes.count else { continue }
            let nodeModel = presentation.nodes[surfaceIndex]
            let visibleCount = nodeModel.isWorking
                ? min(surface.particles.count, max(3, Int(3 + nodeModel.intensity * 15)))
                : 0
            let origin = slotPositions[surfaceIndex]
            let delta = CGPoint(x: corePoint.x - origin.x, y: corePoint.y - origin.y)
            let distance = max(1, hypot(delta.x, delta.y))
            let perpendicular = CGPoint(x: -delta.y / distance, y: delta.x / distance)
            let speedScale = reduceMotion ? 0.3 : 1.0

            for (particleIndex, particle) in surface.particles.enumerated() {
                guard particleIndex < visibleCount else {
                    particle.isHidden = true
                    continue
                }
                particle.isHidden = false
                let duration = max(0.8, nodeModel.travelMs / 1_000) * (0.86 + Double(particleIndex % 5) * 0.06)
                let seed = noise(Double(surfaceIndex * 29 + particleIndex) + 2.7)
                let phase = fmod(elapsed * speedScale / duration + seed + Double(particleIndex) / Double(visibleCount), 1)
                let bend = sin(phase * .pi) * sin(Double(surfaceIndex + 1) * 1.37) * 32
                let wave = sin(elapsed * 2.2 + Double(particleIndex)) * 3.5
                particle.position = CGPoint(
                    x: origin.x + delta.x * phase + perpendicular.x * CGFloat(bend + wave),
                    y: origin.y + delta.y * phase + perpendicular.y * CGFloat(bend + wave)
                )
                let envelope = min(1, phase / 0.08, (1 - phase) / 0.12)
                particle.alpha = CGFloat(max(0, envelope) * (0.45 + nodeModel.intensity * 0.5))
                particle.color = nodeModel.isPressured
                    ? (nodeModel.cpuPercent ?? 0) >= 90 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
                    : particleIndex.isMultiple(of: 5) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green)
                particle.zRotation = atan2(delta.y, delta.x)
                particle.xScale = CGFloat(0.85 + nodeModel.intensity * 0.55)
            }
        }
    }

    private func nodeColor(_ node: FleetLoadNode) -> UIColor {
        guard node.status == "live" else {
            return node.status == "error" ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.muted)
        }
        if node.isPressured {
            return (node.cpuPercent ?? 0) >= 90 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
        }
        if node.intensity >= 0.62 { return UIColor(AmbientTheme.blue) }
        return UIColor(AmbientTheme.green)
    }

    private func displayName(_ name: String) -> String {
        guard name.count > 20 else { return name }
        return "\(name.prefix(19))…"
    }

    private func noise(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

struct FleetLoadSceneView: View {
    let presentation: FleetLoadPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = FleetLoadScene()

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .background(AmbientTheme.background)
            .onAppear {
                scene.isPaused = false
                scene.apply(presentation, reduceMotion: reduceMotion)
            }
            .onDisappear { scene.isPaused = true }
            .onChange(of: presentation) { _, next in
                scene.apply(next, reduceMotion: reduceMotion)
            }
            .onChange(of: reduceMotion) { _, next in
                scene.apply(presentation, reduceMotion: next)
            }
            .accessibilityLabel(
                String(
                    localized: "\(presentation.visual.label) Fleet activity across \(presentation.totalNodeCount) nodes",
                    comment: "VoiceOver description for the Fleet activity animation."
                )
            )
    }
}
