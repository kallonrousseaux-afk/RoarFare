import SpriteKit
import RoarFareCore

final class BattleScene: SKScene {
    private var lane = Lane(length: 900, playerBaseHP: 1000, enemyBaseHP: 1000)
    private var bundledUnits: [UnitDefinition] = []
    private var lastUpdateTime: TimeInterval?
    private var amber: Double = 0
    private let amberPerSecond: Double = 20

    private var enemySpawnTimer: Double = 0
    private let enemySpawnCooldown: Double = 2.0

    private var isGameOver = false

    private struct UnitVisual {
        let container: SKNode
        let hpLabel: SKLabelNode
    }
    private var playerVisuals: [UUID: UnitVisual] = [:]
    private var enemyVisuals: [UUID: UnitVisual] = [:]

    private let amberLabel = SKLabelNode(fontNamed: "Menlo")
    private let playerBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let enemyBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let statusLabel = SKLabelNode(fontNamed: "Menlo")

    override func didMove(to view: SKView) {
        backgroundColor = .black
        bundledUnits = (try? UnitCatalog.loadAll()) ?? []

        amberLabel.fontSize = 18
        amberLabel.horizontalAlignmentMode = .left
        amberLabel.position = CGPoint(x: 20, y: size.height - 30)
        addChild(amberLabel)

        playerBaseLabel.fontSize = 18
        playerBaseLabel.horizontalAlignmentMode = .left
        playerBaseLabel.position = CGPoint(x: 20, y: size.height - 55)
        addChild(playerBaseLabel)

        enemyBaseLabel.fontSize = 18
        enemyBaseLabel.horizontalAlignmentMode = .right
        enemyBaseLabel.position = CGPoint(x: size.width - 20, y: size.height - 55)
        addChild(enemyBaseLabel)

        statusLabel.fontSize = 32
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusLabel.isHidden = true
        addChild(statusLabel)
    }

    func deployPlayerUnit(at index: Int) {
        guard !isGameOver, bundledUnits.indices.contains(index) else { return }
        let unit = bundledUnits[index]
        guard Double(unit.deployCost) <= amber else { return }
        guard lane.deploy(unit, to: .player) else { return }
        amber -= Double(unit.deployCost)
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime

        amber += amberPerSecond * deltaTime

        enemySpawnTimer += deltaTime
        if enemySpawnTimer >= enemySpawnCooldown, let randomUnit = bundledUnits.randomElement() {
            if lane.deploy(randomUnit, to: .enemy) {
                enemySpawnTimer = 0
            }
        }

        lane.tick(deltaTime: deltaTime)

        sync(units: lane.playerUnits, visuals: &playerVisuals, color: .systemBlue)
        sync(units: lane.enemyUnits, visuals: &enemyVisuals, color: .systemRed)
        updateLabels()
        checkGameOver()
    }

    private func sync(units: [DeployedUnit], visuals: inout [UUID: UnitVisual], color: SKColor) {
        var seenIDs = Set<UUID>()
        for unit in units {
            seenIDs.insert(unit.id)
            let visual: UnitVisual
            if let existing = visuals[unit.id] {
                visual = existing
            } else {
                visual = makeVisual(color: color)
                visuals[unit.id] = visual
            }
            visual.container.position = CGPoint(x: xPosition(for: unit.position), y: size.height / 2)
            visual.hpLabel.text = "\(max(0, unit.currentHP))"
        }
        for (id, visual) in visuals where !seenIDs.contains(id) {
            visual.container.removeFromParent()
            visuals.removeValue(forKey: id)
        }
    }

    private func makeVisual(color: SKColor) -> UnitVisual {
        let container = SKNode()
        let shape = SKShapeNode(circleOfRadius: 14)
        shape.fillColor = color
        shape.strokeColor = .white
        container.addChild(shape)

        let hpLabel = SKLabelNode(fontNamed: "Menlo")
        hpLabel.fontSize = 10
        hpLabel.position = CGPoint(x: 0, y: 18)
        container.addChild(hpLabel)

        addChild(container)
        return UnitVisual(container: container, hpLabel: hpLabel)
    }

    private func xPosition(for lanePosition: Double) -> CGFloat {
        let margin: CGFloat = 40
        let usableWidth = size.width - margin * 2
        let fraction = CGFloat(lanePosition / lane.length)
        return margin + usableWidth * fraction
    }

    private func updateLabels() {
        amberLabel.text = "Amber: \(Int(amber))"
        playerBaseLabel.text = "Base: \(max(0, lane.playerBaseHP))"
        enemyBaseLabel.text = "Enemy Base: \(max(0, lane.enemyBaseHP))"
    }

    private func checkGameOver() {
        if lane.enemyBaseHP <= 0 {
            endGame(message: "YOU WIN")
        } else if lane.playerBaseHP <= 0 {
            endGame(message: "YOU LOSE")
        }
    }

    private func endGame(message: String) {
        isGameOver = true
        statusLabel.text = message
        statusLabel.isHidden = false
    }
}
