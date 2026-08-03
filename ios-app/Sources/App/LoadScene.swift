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

enum FleetLoadSceneProfile {
    static let maximumNodeCount = 6
    static let routeParticleCapacity = 32
    static let localParticleCapacity = 18
    static let fieldParticleCapacity = 72

    static func motionScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.3 : 1
    }

    static func routeParticleCount(intensity: Double, isWorking: Bool) -> Int {
        guard isWorking else { return 0 }
        return min(routeParticleCapacity, max(8, Int(8 + intensity * 24)))
    }

    static func localParticleCount(intensity: Double, isWorking: Bool) -> Int {
        guard isWorking else { return 0 }
        return min(localParticleCapacity, max(5, Int(5 + intensity * 13)))
    }

    static func slotIndices(nodeCount: Int) -> [Int] {
        switch min(max(nodeCount, 0), maximumNodeCount) {
        case 0: []
        case 1: [1]
        case 2: [1, 4]
        case 3: [0, 2, 4]
        case 4: [0, 2, 3, 5]
        case 5: [0, 1, 2, 3, 5]
        default: Array(0..<maximumNodeCount)
        }
    }
}

@MainActor
final class FleetLoadScene: SKScene {
    private struct NodeSurface {
        let container: SKNode
        let bay: SKShapeNode
        let artwork: SKSpriteNode
        let screen: SKShapeNode
        let screenBars: [SKSpriteNode]
        let statusDot: SKShapeNode
        let name: SKLabelNode
        let detail: SKLabelNode
        let port: SKShapeNode
        let heatBars: [SKSpriteNode]
        let path: SKShapeNode
        let routeParticles: [SKSpriteNode]
        let localParticles: [SKSpriteNode]
    }

    private let logicalSize = CGSize(width: 960, height: 540)
    private let corePoint = CGPoint(x: 480, y: 270)
    private let slotPositions = [
        CGPoint(x: 142, y: 424),
        CGPoint(x: 142, y: 270),
        CGPoint(x: 142, y: 116),
        CGPoint(x: 818, y: 424),
        CGPoint(x: 818, y: 270),
        CGPoint(x: 818, y: 116),
    ]
    private var presentation = FleetLoadPresentation(status: .unavailable())
    private var surfaces: [NodeSurface] = []
    private var coreRings: [SKShapeNode] = []
    private var coreBars: [SKSpriteNode] = []
    private var coreParticles: [SKSpriteNode] = []
    private var fieldParticles: [SKSpriteNode] = []
    private var queueNodes: [SKSpriteNode] = []
    private var heatNodes: [SKSpriteNode] = []
    private var startTime: TimeInterval?
    private var reduceMotion = false

    private var activeSlotIndices: [Int] {
        FleetLoadSceneProfile.slotIndices(nodeCount: presentation.nodes.count)
    }

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
        buildCoreFlow()
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
        animateCoreFlow(elapsed)
        animateFieldFlow(elapsed)
        animateQueue(elapsed)
        animateHeat(elapsed)
    }

    private func buildGrid() {
        let grid = SKNode()
        grid.zPosition = -30
        for x in stride(from: 0, through: Int(logicalSize.width), by: 24) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.14),
                size: CGSize(width: 1, height: logicalSize.height)
            )
            line.position = CGPoint(x: CGFloat(x), y: logicalSize.height / 2)
            grid.addChild(line)
        }
        for y in stride(from: 0, through: Int(logicalSize.height), by: 24) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.14),
                size: CGSize(width: logicalSize.width, height: 1)
            )
            line.position = CGPoint(x: logicalSize.width / 2, y: CGFloat(y))
            grid.addChild(line)
        }
        addChild(grid)

        for y in [38.0, 192.0, 346.0, 500.0] {
            let floor = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.38, blue: 0.43, alpha: 0.28),
                size: CGSize(width: logicalSize.width - 28, height: 2)
            )
            floor.position = CGPoint(x: logicalSize.width / 2, y: y)
            floor.zPosition = -24
            addChild(floor)
        }

        let corridor = SKShapeNode(rectOf: CGSize(width: 372, height: 500), cornerRadius: 3)
        corridor.position = corePoint
        corridor.fillColor = UIColor(red: 0.015, green: 0.035, blue: 0.042, alpha: 0.56)
        corridor.strokeColor = UIColor(AmbientTheme.blue).withAlphaComponent(0.12)
        corridor.lineWidth = 2
        corridor.zPosition = -22
        addChild(corridor)

        for y in stride(from: 7, through: Int(logicalSize.height), by: 8) {
            let scanline = SKSpriteNode(
                color: UIColor(red: 0.64, green: 0.76, blue: 0.82, alpha: 0.018),
                size: CGSize(width: logicalSize.width, height: 1)
            )
            scanline.position = CGPoint(x: logicalSize.width / 2, y: CGFloat(y))
            scanline.zPosition = 30
            addChild(scanline)
        }
    }

    private func buildCore() {
        let console = SKShapeNode(rectOf: CGSize(width: 186, height: 142), cornerRadius: 4)
        console.position = corePoint
        console.fillColor = UIColor(red: 0.025, green: 0.065, blue: 0.073, alpha: 0.96)
        console.strokeColor = UIColor(AmbientTheme.blue).withAlphaComponent(0.48)
        console.lineWidth = 3
        console.zPosition = 2
        addChild(console)

        let consoleInset = SKShapeNode(rectOf: CGSize(width: 158, height: 92), cornerRadius: 2)
        consoleInset.position = CGPoint(x: corePoint.x, y: corePoint.y + 8)
        consoleInset.fillColor = UIColor(red: 0.012, green: 0.035, blue: 0.039, alpha: 0.98)
        consoleInset.strokeColor = UIColor(AmbientTheme.green).withAlphaComponent(0.28)
        consoleInset.lineWidth = 2
        consoleInset.zPosition = 3
        addChild(consoleInset)

        for radius in [92.0, 76.0, 40.0] {
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.position = corePoint
            ring.fillColor = .clear
            ring.strokeColor = radius == 92
                ? UIColor(AmbientTheme.blue).withAlphaComponent(0.22)
                : UIColor(AmbientTheme.green).withAlphaComponent(0.58)
            ring.lineWidth = radius == 40 ? 3 : 2
            ring.zPosition = radius == 40 ? 4 : 1
            coreRings.append(ring)
            addChild(ring)
        }

        let icon = SKLabelNode(fontNamed: "Menlo-Bold")
        icon.text = "OPL"
        icon.fontSize = 21
        icon.fontColor = UIColor(AmbientTheme.green)
        icon.verticalAlignmentMode = .center
        icon.horizontalAlignmentMode = .center
        icon.position = CGPoint(x: corePoint.x, y: corePoint.y + 17)
        icon.zPosition = 7
        addChild(icon)

        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = "FLEET"
        label.fontSize = 10
        label.fontColor = UIColor(AmbientTheme.muted)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: corePoint.x, y: corePoint.y - 7)
        label.zPosition = 7
        addChild(label)

        for index in 0..<9 {
            let bar = SKSpriteNode(
                color: index.isMultiple(of: 4) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green),
                size: CGSize(width: CGFloat(20 + (index * 17) % 54), height: 3)
            )
            bar.anchorPoint = CGPoint(x: 0, y: 0.5)
            bar.position = CGPoint(
                x: corePoint.x - 68 + CGFloat(index % 3) * 48,
                y: corePoint.y + 51 - CGFloat(index / 3) * 11
            )
            bar.zPosition = 7
            coreBars.append(bar)
            addChild(bar)
        }

        let inbound = SKLabelNode(fontNamed: "Menlo-Bold")
        inbound.text = "ROUTER  /  TASK QUEUE"
        inbound.fontSize = 9
        inbound.fontColor = UIColor(AmbientTheme.muted)
        inbound.position = CGPoint(x: corePoint.x, y: corePoint.y - 51)
        inbound.zPosition = 7
        addChild(inbound)
    }

    private func buildCoreFlow() {
        for index in 0..<FleetLoadSceneProfile.fieldParticleCapacity {
            let particle = SKSpriteNode(
                color: index.isMultiple(of: 5) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green),
                size: CGSize(width: index.isMultiple(of: 8) ? 12 : 5, height: 3)
            )
            particle.zPosition = 0
            particle.isHidden = true
            fieldParticles.append(particle)
            addChild(particle)
        }

        for index in 0..<84 {
            let particle = SKSpriteNode(
                color: index.isMultiple(of: 6) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green),
                size: CGSize(width: index.isMultiple(of: 9) ? 10 : 5, height: index.isMultiple(of: 9) ? 4 : 5)
            )
            particle.zPosition = 6
            particle.isHidden = true
            coreParticles.append(particle)
            addChild(particle)
        }

        for index in 0..<24 {
            let queue = SKSpriteNode(
                color: index.isMultiple(of: 5) ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber),
                size: CGSize(width: index.isMultiple(of: 4) ? 11 : 6, height: 6)
            )
            queue.zPosition = 10
            queue.isHidden = true
            queueNodes.append(queue)
            addChild(queue)
        }

        for _ in 0..<10 {
            let heat = SKSpriteNode(
                color: UIColor(AmbientTheme.amber),
                size: CGSize(width: 8, height: 22)
            )
            heat.zPosition = 11
            heat.isHidden = true
            heatNodes.append(heat)
            addChild(heat)
        }
    }

    private func buildNodeSurfaces() {
        for (index, position) in slotPositions.enumerated() {
            let isLeft = index < 3
            let path = SKShapeNode()
            path.strokeColor = UIColor(AmbientTheme.line)
            path.lineWidth = 1.5
            path.zPosition = -2
            addChild(path)

            let container = SKNode()
            container.position = position
            container.zPosition = 8
            addChild(container)

            let bay = SKShapeNode(rectOf: CGSize(width: 268, height: 130), cornerRadius: 4)
            bay.fillColor = UIColor(red: 0.028, green: 0.048, blue: 0.056, alpha: 0.96)
            bay.strokeColor = UIColor(AmbientTheme.line)
            bay.lineWidth = 2
            container.addChild(bay)

            let bayFloor = SKSpriteNode(
                color: UIColor(red: 0.11, green: 0.28, blue: 0.31, alpha: 0.52),
                size: CGSize(width: 242, height: 2)
            )
            bayFloor.position = CGPoint(x: 0, y: -48)
            bayFloor.zPosition = 1
            container.addChild(bayFloor)

            let artwork = SKSpriteNode(texture: SKTexture(imageNamed: "operator-workbench.webp"))
            artwork.texture?.filteringMode = .nearest
            artwork.size = CGSize(width: 132, height: 132)
            artwork.position = CGPoint(x: isLeft ? -66 : 66, y: -3)
            artwork.alpha = 0.82
            artwork.zPosition = 2
            artwork.xScale = isLeft ? 1 : -1
            container.addChild(artwork)

            let screenX: CGFloat = isLeft ? -32 : 32
            let screen = SKShapeNode(rectOf: CGSize(width: 38, height: 28), cornerRadius: 1)
            screen.position = CGPoint(x: screenX, y: 26)
            screen.fillColor = UIColor(red: 0.015, green: 0.07, blue: 0.075, alpha: 0.84)
            screen.strokeColor = UIColor(AmbientTheme.blue).withAlphaComponent(0.45)
            screen.lineWidth = 1
            screen.zPosition = 4
            container.addChild(screen)

            var screenBars: [SKSpriteNode] = []
            for barIndex in 0..<4 {
                let bar = SKSpriteNode(
                    color: barIndex.isMultiple(of: 3) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green),
                    size: CGSize(width: CGFloat(12 + barIndex * 5), height: 2)
                )
                bar.anchorPoint = CGPoint(x: 0, y: 0.5)
                bar.position = CGPoint(x: screenX - 15, y: 35 - CGFloat(barIndex * 6))
                bar.zPosition = 5
                screenBars.append(bar)
                container.addChild(bar)
            }

            let statusDot = SKShapeNode(circleOfRadius: 5)
            statusDot.position = CGPoint(x: isLeft ? 6 : -120, y: 44)
            statusDot.fillColor = UIColor(AmbientTheme.muted)
            statusDot.strokeColor = .clear
            statusDot.zPosition = 5
            container.addChild(statusDot)

            let name = SKLabelNode(fontNamed: "Menlo-Bold")
            name.fontSize = 13
            name.fontColor = .white
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: isLeft ? 17 : -109, y: 44)
            name.zPosition = 5
            container.addChild(name)

            let detail = SKLabelNode(fontNamed: "Menlo")
            detail.fontSize = 9
            detail.fontColor = UIColor(AmbientTheme.muted)
            detail.horizontalAlignmentMode = .left
            detail.verticalAlignmentMode = .center
            detail.position = CGPoint(x: isLeft ? 6 : -120, y: 20)
            detail.zPosition = 5
            container.addChild(detail)

            let port = SKShapeNode(rectOf: CGSize(width: 13, height: 13), cornerRadius: 1)
            port.position = CGPoint(x: isLeft ? 134 : -134, y: 0)
            port.fillColor = UIColor(red: 0.02, green: 0.07, blue: 0.075, alpha: 1)
            port.strokeColor = UIColor(AmbientTheme.green)
            port.lineWidth = 2
            port.zPosition = 8
            container.addChild(port)

            var heatBars: [SKSpriteNode] = []
            for heatIndex in 0..<4 {
                let heat = SKSpriteNode(
                    color: UIColor(AmbientTheme.amber),
                    size: CGSize(width: 5, height: CGFloat(8 + heatIndex * 5))
                )
                heat.position = CGPoint(x: isLeft ? 110 + CGFloat(heatIndex * 7) : -110 - CGFloat(heatIndex * 7), y: -44)
                heat.zPosition = 6
                heat.isHidden = true
                heatBars.append(heat)
                container.addChild(heat)
            }

            var routeParticles: [SKSpriteNode] = []
            for particleIndex in 0..<FleetLoadSceneProfile.routeParticleCapacity {
                let particle = SKSpriteNode(
                    color: particleIndex.isMultiple(of: 5)
                        ? UIColor(AmbientTheme.blue)
                        : UIColor(AmbientTheme.green),
                    size: CGSize(width: particleIndex.isMultiple(of: 7) ? 12 : 6, height: 4)
                )
                particle.zPosition = 7
                particle.isHidden = true
                routeParticles.append(particle)
                addChild(particle)
            }

            var localParticles: [SKSpriteNode] = []
            for particleIndex in 0..<FleetLoadSceneProfile.localParticleCapacity {
                let particle = SKSpriteNode(
                    color: particleIndex.isMultiple(of: 4) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green),
                    size: CGSize(width: particleIndex.isMultiple(of: 6) ? 7 : 4, height: 4)
                )
                particle.zPosition = 6
                particle.isHidden = true
                localParticles.append(particle)
                container.addChild(particle)
            }

            surfaces.append(
                NodeSurface(
                    container: container,
                    bay: bay,
                    artwork: artwork,
                    screen: screen,
                    screenBars: screenBars,
                    statusDot: statusDot,
                    name: name,
                    detail: detail,
                    port: port,
                    heatBars: heatBars,
                    path: path,
                    routeParticles: routeParticles,
                    localParticles: localParticles
                )
            )
            updatePath(path, from: position, slotIndex: index)
        }
    }

    private func updatePath(_ node: SKShapeNode, from point: CGPoint, slotIndex: Int) {
        let path = CGMutablePath()
        let isLeft = slotIndex < 3
        let origin = CGPoint(x: point.x + (isLeft ? 134 : -134), y: point.y)
        path.move(to: origin)
        let bend = CGPoint(
            x: (origin.x + corePoint.x) / 2,
            y: (origin.y + corePoint.y) / 2 + CGFloat((slotIndex % 3 - 1) * 28)
        )
        path.addQuadCurve(to: corePoint, control: bend)
        node.path = path
    }

    private func updateSurfaces() {
        let stateColor = UIColor(AmbientTheme.statusColor(presentation.visual.state))
        coreRings.last?.strokeColor = stateColor
        let activeSlots = Set(activeSlotIndices)
        for (index, surface) in surfaces.enumerated() {
            guard activeSlots.contains(index),
                  let nodeIndex = activeSlotIndices.firstIndex(of: index) else {
                surface.container.isHidden = true
                surface.path.isHidden = true
                surface.routeParticles.forEach { $0.isHidden = true }
                surface.localParticles.forEach { $0.isHidden = true }
                continue
            }
            let node = presentation.nodes[nodeIndex]
            surface.container.isHidden = false
            surface.path.isHidden = false
            surface.name.text = displayName(node.name)
            surface.name.fontSize = node.name.count > 16 ? 11 : node.name.count > 12 ? 13 : 15
            surface.detail.text = node.status == "live"
                ? "\(MetricFormat.tps(node.tps)) TPS  ·  \(MetricFormat.integer(node.sessions)) ACTIVE"
                : node.status.uppercased()
            let color = nodeColor(node)
            surface.statusDot.fillColor = color
            surface.bay.strokeColor = color.withAlphaComponent(node.status == "live" ? 0.62 : 0.28)
            surface.screen.strokeColor = color.withAlphaComponent(node.isWorking ? 0.72 : 0.28)
            surface.port.strokeColor = color
            surface.path.strokeColor = color.withAlphaComponent(node.isWorking ? 0.42 : 0.14)
            surface.name.fontColor = node.status == "live" ? .white : UIColor(AmbientTheme.muted)
            surface.detail.fontColor = node.isWorking ? color : UIColor(AmbientTheme.muted)
            surface.artwork.alpha = node.status == "live" ? 0.88 : 0.32
            for heatBar in surface.heatBars {
                heatBar.color = (node.cpuPercent ?? 0) >= 90 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
            }
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
        for (index, bar) in coreBars.enumerated() {
            let pulse = 0.5 + 0.5 * sin(elapsed * speed * 2.2 + Double(index) * 0.73)
            bar.alpha = 0.25 + CGFloat(max(0.08, presentation.visual.activity)) * CGFloat(pulse) * 0.74
            bar.xScale = 0.52 + CGFloat(pulse) * 0.48
        }
    }

    private func animateFlows(_ elapsed: TimeInterval) {
        for (surfaceIndex, surface) in surfaces.enumerated() {
            guard let nodeIndex = activeSlotIndices.firstIndex(of: surfaceIndex) else { continue }
            let nodeModel = presentation.nodes[nodeIndex]
            let visibleCount = FleetLoadSceneProfile.routeParticleCount(
                intensity: nodeModel.intensity,
                isWorking: nodeModel.isWorking
            )
            let localCount = FleetLoadSceneProfile.localParticleCount(
                intensity: nodeModel.intensity,
                isWorking: nodeModel.isWorking
            )
            let isLeft = surfaceIndex < 3
            let origin = CGPoint(
                x: slotPositions[surfaceIndex].x + (isLeft ? 134 : -134),
                y: slotPositions[surfaceIndex].y
            )
            let delta = CGPoint(x: corePoint.x - origin.x, y: corePoint.y - origin.y)
            let distance = max(1, hypot(delta.x, delta.y))
            let perpendicular = CGPoint(x: -delta.y / distance, y: delta.x / distance)
            let speedScale = FleetLoadSceneProfile.motionScale(reduceMotion: reduceMotion)

            for (particleIndex, particle) in surface.routeParticles.enumerated() {
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
                particle.xScale = CGFloat(1.05 + nodeModel.intensity * 0.78)
            }

            for (particleIndex, particle) in surface.localParticles.enumerated() {
                guard particleIndex < localCount else {
                    particle.isHidden = true
                    continue
                }
                particle.isHidden = false
                let phase = fmod(
                    elapsed * speedScale * (0.36 + nodeModel.intensity * 0.9)
                        + noise(Double(surfaceIndex * 61 + particleIndex))
                        + Double(particleIndex) / Double(max(localCount, 1)),
                    1
                )
                let direction: CGFloat = isLeft ? 1 : -1
                let sweep = CGFloat(phase) * 98 * direction
                particle.position = CGPoint(
                    x: (isLeft ? -94 : 94) + sweep,
                    y: -34 + CGFloat(noise(Double(particleIndex) * 3.7) * 60)
                        + CGFloat(sin(elapsed * 2.4 + Double(particleIndex)) * 4)
                )
                particle.alpha = CGFloat(min(1, phase / 0.1, (1 - phase) / 0.12)) * 0.78
                particle.color = nodeModel.isPressured
                    ? (nodeModel.cpuPercent ?? 0) >= 90 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
                    : particleIndex.isMultiple(of: 4) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green)
            }

            for (barIndex, bar) in surface.screenBars.enumerated() {
                let pulse = 0.5 + 0.5 * sin(elapsed * speedScale * 3 + Double(surfaceIndex * 7 + barIndex))
                bar.alpha = nodeModel.isWorking ? 0.35 + CGFloat(pulse) * 0.65 : 0.18
                bar.xScale = 0.52 + CGFloat(pulse) * CGFloat(0.26 + nodeModel.intensity * 0.36)
            }
            surface.port.alpha = nodeModel.isWorking
                ? 0.58 + CGFloat(sin(elapsed * speedScale * 4 + Double(surfaceIndex)) * 0.28)
                : 0.32
            for (heatIndex, heat) in surface.heatBars.enumerated() {
                heat.isHidden = !nodeModel.isPressured
                guard !heat.isHidden else { continue }
                heat.alpha = 0.28 + CGFloat(nodeModel.intensity) * 0.58
                heat.yScale = 0.7 + CGFloat(0.3 * sin(elapsed * speedScale * 3.2 + Double(heatIndex)))
            }
        }
    }

    private func animateCoreFlow(_ elapsed: TimeInterval) {
        let visual = presentation.visual
        let activeCount = visual.clusterCount == 0
            ? 0
            : min(coreParticles.count, Int(18 + visual.taskDensity * 52 + visual.parallel * 14))
        let speedScale = FleetLoadSceneProfile.motionScale(reduceMotion: reduceMotion)
        let radiusX = 72 + visual.activity * 52
        let radiusY = 52 + visual.parallel * 42

        for (index, particle) in coreParticles.enumerated() {
            guard index < activeCount else {
                particle.isHidden = true
                continue
            }
            particle.isHidden = false
            let orbit = elapsed * speedScale * (0.42 + visual.tempo * 0.26)
                + Double(index) * 2.399
            let layer = 0.55 + noise(Double(index) * 6.31) * 0.75
            let flutter = sin(elapsed * speedScale * 2.8 + Double(index)) * (4 + visual.activity * 9)
            particle.position = CGPoint(
                x: corePoint.x + CGFloat(cos(orbit) * radiusX * layer + flutter),
                y: corePoint.y + CGFloat(sin(orbit * 1.13) * radiusY * layer)
            )
            particle.alpha = 0.28 + CGFloat(visual.activity) * 0.62
            if visual.pressure > 0.28 && index.isMultiple(of: 3) {
                particle.color = visual.pressure > 0.74 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
            } else {
                particle.color = index.isMultiple(of: 6) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green)
            }
        }
    }

    private func animateFieldFlow(_ elapsed: TimeInterval) {
        let visual = presentation.visual
        let activeCount = visual.clusterCount == 0
            ? 0
            : min(fieldParticles.count, Int(16 + visual.taskDensity * 48 + visual.parallel * 8))
        let speedScale = FleetLoadSceneProfile.motionScale(reduceMotion: reduceMotion)
        let travelMs = max(1_200, visual.travelMs)
        for (index, particle) in fieldParticles.enumerated() {
            guard index < activeCount else {
                particle.isHidden = true
                continue
            }
            particle.isHidden = false
            let lane = index % 3
            let seed = noise(Double(index) * 4.83 + 6.2)
            let phase = fmod(
                elapsed * speedScale / (travelMs / 1_000 * (0.72 + seed * 0.48)) + seed,
                1
            )
            let laneY = [188.0, 270.0, 352.0][lane]
            let wave = sin(elapsed * speedScale * (1.6 + seed) + Double(index)) * (3 + visual.activity * 12)
            particle.position = CGPoint(
                x: -24 + CGFloat(phase) * (logicalSize.width + 48),
                y: laneY + wave + CGFloat(noise(Double(index) * 2.91) - 0.5) * (10 + visual.activity * 28)
            )
            let envelope = min(1, phase / 0.08, (1 - phase) / 0.1)
            particle.alpha = CGFloat(max(0, envelope) * (0.18 + visual.activity * 0.32))
            particle.color = visual.pressure > 0.7 && index.isMultiple(of: 4)
                ? UIColor(AmbientTheme.red)
                : index.isMultiple(of: 5) ? UIColor(AmbientTheme.blue) : UIColor(AmbientTheme.green)
            particle.xScale = CGFloat(0.8 + visual.tempo * 0.55)
        }
    }

    private func animateQueue(_ elapsed: TimeInterval) {
        let visual = presentation.visual
        let count = visual.queueDepth <= 0.05
            ? 0
            : min(queueNodes.count, Int(4 + visual.queueDepth * 20))
        let speedScale = FleetLoadSceneProfile.motionScale(reduceMotion: reduceMotion)
        for (index, node) in queueNodes.enumerated() {
            guard index < count else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let column = CGFloat(index % 6)
            let row = CGFloat((index / 2) % 5)
            node.position = CGPoint(
                x: corePoint.x + side * (102 + column * 10),
                y: corePoint.y - 34 + row * 17
                    + CGFloat(sin(elapsed * speedScale * 4 + Double(index)) * (2 + visual.pressure * 7))
            )
            node.alpha = 0.3 + CGFloat(index % 4) * 0.13
            node.color = visual.pressure > 0.74 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
        }
    }

    private func animateHeat(_ elapsed: TimeInterval) {
        let visual = presentation.visual
        let speedScale = FleetLoadSceneProfile.motionScale(reduceMotion: reduceMotion)
        for (index, node) in heatNodes.enumerated() {
            node.isHidden = visual.heat <= 0.08
            guard !node.isHidden else { continue }
            node.position = CGPoint(
                x: corePoint.x - 82 + CGFloat(index) * 18,
                y: corePoint.y - 82 + CGFloat(sin(elapsed * speedScale * 3 + Double(index)) * 5)
            )
            node.alpha = 0.12 + CGFloat(visual.heat) * 0.62
            node.color = visual.pressure > 0.7 ? UIColor(AmbientTheme.red) : UIColor(AmbientTheme.amber)
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
