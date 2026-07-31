import SpriteKit
import SwiftUI

struct PetAnimationFrame: Equatable, Sendable {
    let column: Int
    let durationMilliseconds: Double
}

struct PetAnimationPlayback: Equatable, Sendable {
    let row: Int
    let frames: [PetAnimationFrame]

    var durationMilliseconds: Double {
        frames.reduce(0) { $0 + $1.durationMilliseconds }
    }

    static func forState(_ state: String) -> PetAnimationPlayback {
        let definition: (row: Int, durations: [Double], scale: Double) = switch state {
        case "jumping": (4, [140, 140, 140, 140, 280], 1)
        case "failed": (5, [140, 140, 140, 140, 140, 140, 140, 240], 1)
        case "waiting": (6, [150, 150, 150, 150, 150, 260], 1)
        case "running": (7, [120, 120, 120, 120, 120, 220], 1)
        case "review": (8, [150, 150, 150, 150, 150, 280], 1)
        case "waving": (3, [140, 140, 140, 280], 1)
        default: (0, [280, 110, 110, 140, 140, 320], 6)
        }
        return PetAnimationPlayback(
            row: definition.row,
            frames: definition.durations.enumerated().map { column, duration in
                PetAnimationFrame(
                    column: column,
                    durationMilliseconds: duration * definition.scale
                )
            }
        )
    }

    func frameIndex(atElapsedMilliseconds elapsed: Double) -> Int {
        guard !frames.isEmpty, durationMilliseconds > 0 else { return 0 }
        let loopElapsed = max(0, elapsed).truncatingRemainder(dividingBy: durationMilliseconds)
        var frameEnd = 0.0
        for (index, frame) in frames.enumerated() {
            frameEnd += frame.durationMilliseconds
            if loopElapsed < frameEnd {
                return index
            }
        }
        return 0
    }
}

struct PetAtlasLayout: Equatable, Sendable {
    static let columns = 8
    static let cellWidth: CGFloat = 192
    static let cellHeight: CGFloat = 208

    let rowCount: Int

    init(spriteVersionNumber: Int, imageSize: CGSize?) {
        let versionRows = spriteVersionNumber == 2 ? 11 : 9
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            rowCount = versionRows
            return
        }

        let atlasCellWidth = imageSize.width / CGFloat(Self.columns)
        let atlasCellHeight = atlasCellWidth * Self.cellHeight / Self.cellWidth
        let detectedRows = Int((imageSize.height / atlasCellHeight).rounded())
        rowCount = [9, 11].contains(detectedRows) ? detectedRows : versionRows
    }

    func textureRect(row: Int, column: Int) -> CGRect {
        let width = 1.0 / CGFloat(Self.columns)
        let height = 1.0 / CGFloat(rowCount)
        return CGRect(
            x: CGFloat(column) * width,
            y: 1 - CGFloat(row + 1) * height,
            width: width,
            height: height
        )
    }
}

@MainActor
final class PetScene: SKScene {
    private let gridNode = SKNode()
    private let petNode = SKSpriteNode()
    private let floorNode = SKSpriteNode(
        color: UIColor(AmbientTheme.green.opacity(0.22)),
        size: CGSize(width: 380, height: 2)
    )
    private var sheet: SKTexture?
    private var atlasLayout = PetAtlasLayout(spriteVersionNumber: 1, imageSize: nil)
    private var playback = PetAnimationPlayback.forState("idle")
    private var frameIndex = 0
    private var playbackStartedAt: TimeInterval?

    override init() {
        super.init(size: CGSize(width: 640, height: 420))
        scaleMode = .resizeFill
        backgroundColor = UIColor(AmbientTheme.background)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else { return }
        view.preferredFramesPerSecond = 30
        view.ignoresSiblingOrder = true
        gridNode.zPosition = -2
        addChild(gridNode)
        petNode.texture?.filteringMode = .nearest
        addChild(petNode)
        addChild(floorNode)
        layoutScene()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }

    func apply(pet: PetStatus, image: UIImage?) {
        playback = PetAnimationPlayback.forState(pet.state)
        atlasLayout = PetAtlasLayout(
            spriteVersionNumber: pet.spriteVersionNumber,
            imageSize: image?.size
        )
        if let image {
            sheet = SKTexture(image: image)
        } else {
            atlasLayout = PetAtlasLayout(spriteVersionNumber: 1, imageSize: nil)
            sheet = SKTexture(imageNamed: "spritesheet.webp")
        }
        sheet?.filteringMode = .nearest
        frameIndex = 0
        playbackStartedAt = nil
        updateFrame()
    }

    override func update(_ currentTime: TimeInterval) {
        guard sheet != nil else { return }
        if playbackStartedAt == nil {
            playbackStartedAt = currentTime
        }
        let elapsed = (currentTime - (playbackStartedAt ?? currentTime)) * 1_000
        let nextFrameIndex = playback.frameIndex(atElapsedMilliseconds: elapsed)
        if nextFrameIndex != frameIndex {
            frameIndex = nextFrameIndex
            updateFrame()
        }
        petNode.position.y = restingPetY + CGFloat(sin(currentTime * 2.3) * 2)
    }

    private func updateFrame() {
        guard let sheet else { return }
        let rect = atlasLayout.textureRect(
            row: playback.row,
            column: playback.frames[frameIndex].column
        )
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = .nearest
        petNode.texture = texture
    }

    private func buildGrid() {
        gridNode.removeAllChildren()
        for x in stride(from: 0, through: Int(size.width), by: 36) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.2),
                size: CGSize(width: 1, height: size.height)
            )
            line.position = CGPoint(x: CGFloat(x), y: size.height / 2)
            gridNode.addChild(line)
        }
        for y in stride(from: 0, through: Int(size.height), by: 36) {
            let line = SKSpriteNode(
                color: UIColor(red: 0.14, green: 0.21, blue: 0.24, alpha: 0.2),
                size: CGSize(width: size.width, height: 1)
            )
            line.position = CGPoint(x: size.width / 2, y: CGFloat(y))
            gridNode.addChild(line)
        }
    }

    private var restingPetY: CGFloat {
        size.height / 2 + 10
    }

    private func layoutScene() {
        guard size.width > 0, size.height > 0 else { return }
        buildGrid()
        let petHeight = min(300, max(180, size.height * 0.72))
        petNode.size = CGSize(
            width: petHeight * PetAtlasLayout.cellWidth / PetAtlasLayout.cellHeight,
            height: petHeight
        )
        petNode.position = CGPoint(x: size.width / 2, y: restingPetY)
        floorNode.size = CGSize(width: min(380, max(120, size.width - 32)), height: 2)
        floorNode.position = CGPoint(x: size.width / 2, y: max(40, size.height * 0.13))
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
