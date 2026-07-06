import SwiftUI
import SpriteKit
import RoarFareCore

struct ContentView: View {
    @State private var scene: BattleScene = {
        let scene = BattleScene(size: CGSize(width: 400, height: 300))
        scene.scaleMode = .resizeFill
        return scene
    }()
    private let bundledUnits = (try? UnitCatalog.loadAll()) ?? []

    var body: some View {
        VStack(spacing: 0) {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(bundledUnits.enumerated()), id: \.offset) { index, unit in
                        Button(unit.name) {
                            scene.deployPlayerUnit(at: index)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}
