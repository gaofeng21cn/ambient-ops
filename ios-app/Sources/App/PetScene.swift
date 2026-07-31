import SpriteKit
import SwiftUI

@MainActor
final class PetScene: SKScene {
    private let petNode = SKSpriteNode()
    private var sheet: SKTexture?
    private var rowCount = 9
    private var row = 0
    private var frameIndex = 0
    private var lastFrameAt: TimeInterval = 0
    private var frameDuration: TimeInterval = 0.16

    override init() {
        super.init(size: CGSize(width: 640, height: 420))
        scaleMode = .aspectFill
        backgroundColor = UIColor(AmbientTheme.background)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        buildGrid()
        petNode.size = CGSize(width: 270, height: 270)
        petNode.position = CGPoint(x: size.width / 2, y: size.height / 2 + 18)
        petNode.texture?.filteringMode = .nearest
        addChild(petNode)

        let floor = SKSpriteNode(
            color: UIColor(AmbientTheme.green.opacity(0.22)),
            size: CGSize(width: 380, height: 2)
        )
        floor.position = CGPoint(x: size.width / 2, y: 72)
        addChild(floor)
    }

    func apply(pet: PetStatus, image: UIImage?) {
        rowCount = pet.spriteVersionNumber == 2 ? 11 : 9
        row = switch pet.state {
        case "running": 7
        case "waiting": 6
        case "review": 8
        case "failed": 5
        default: 0
        }
        frameDuration = pet.state == "running" ? 0.12 : pet.state == "idle" ? 0.48 : 0.16
        if let image {
            sheet = SKTexture(image: image)
        } else {
            sheet = SKTexture(imageNamed: "spritesheet.webp")
        }
        sheet?.filteringMode = .nearest
        frameIndex = 0
        updateFrame()
    }

    override func update(_ currentTime: TimeInterval) {
        guard sheet != nil, currentTime - lastFrameAt >= frameDuration else { return }
        lastFrameAt = currentTime
        frameIndex = (frameIndex + 1) % 8
        updateFrame()
        petNode.position.y = size.height / 2 + 18 + CGFloat(sin(currentTime * 2.3) * 2)
    }

    private func updateFrame() {
        guard let sheet else { return }
        let width = 1.0 / 8.0
        let height = 1.0 / CGFloat(rowCount)
        let rect = CGRect(
            x: CGFloat(frameIndex) * width,
            y: 1 - CGFloat(row + 1) * height,
            width: width,
            height: height
        )
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = .nearest
        petNode.texture = texture
    }

    private func buildGrid() {
        for x in stride(from: 0, through: Int(size.width), by: 36) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.2),
                size: CGSize(width: 1, height: size.height)
            )
            line.position = CGPoint(x: CGFloat(x), y: size.height / 2)
            line.zPosition = -2
            addChild(line)
        }
        for y in stride(from: 0, through: Int(size.height), by: 36) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.2),
                size: CGSize(width: size.width, height: 1)
            )
            line.position = CGPoint(x: size.width / 2, y: CGFloat(y))
            line.zPosition = -2
            addChild(line)
        }
    }
}

struct PetSceneView: View {
    let pet: PetStatus
    let serverURL: URL?
    @State private var scene = PetScene()

    var body: some View {
        SpriteView(scene: scene)
            .task(id: "\(pet.assetHash ?? "legacy"):\(pet.state)") {
                let image = await loadRemoteImage()
                scene.apply(pet: pet, image: image)
            }
            .onAppear { scene.isPaused = false }
            .onDisappear { scene.isPaused = true }
            .accessibilityLabel("\(pet.displayName), \(pet.state)")
    }

    private func loadRemoteImage() async -> UIImage? {
        guard let path = pet.assetUrl,
              path != "/pets/ledger-owl/spritesheet.webp",
              let serverURL,
              let url = URL(string: path, relativeTo: serverURL)?.absoluteURL,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return UIImage(data: data)
    }
}
