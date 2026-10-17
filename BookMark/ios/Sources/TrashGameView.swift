import SwiftUI
import SpriteKit
import UIKit
import AudioToolbox

// ゴミ箱ミニゲーム。丸まった付箋をフリックしてゴミ箱に投げ入れる。
// SpriteKit で物理演算（重力・跳ね返り・床・ゴミ箱の縁）。

struct TrashGameView: View {
    let sticky: Sticky
    var onSuccess: () -> Void
    var onDismiss: () -> Void

    @State private var successShown = false
    @State private var scene: TrashScene?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.09).ignoresSafeArea()

                SpriteView(scene: buildScene(size: geo.size))
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Button("スキップ") { onDismiss() }
                            .font(.subheadline).bold()
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        Text("ゴミ箱に投げ入れよう")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 18).padding(.top, 16)
                    Spacer()
                    Text("フリックして投げる・外れたら拾い直せる")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 12)
                }

                if successShown {
                    VStack(spacing: 12) {
                        Text("🎉").font(.system(size: 60))
                        Text("ポイッ！").font(.title).bold().foregroundStyle(.white)
                        Text("付箋を覚えた！").foregroundStyle(.white.opacity(0.8))
                        Button("閉じる") { onDismiss() }
                            .buttonStyle(.borderedProminent).tint(.white)
                            .foregroundStyle(.black)
                            .padding(.top, 8)
                    }
                    .padding(40)
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(), value: successShown)
    }

    private func buildScene(size: CGSize) -> TrashScene {
        if let s = scene { return s }
        let s = TrashScene(size: size)
        s.scaleMode = .resizeFill
        s.stickyUIColor = UIColor(sticky.color.color)
        s.onSuccess = {
            AudioServicesPlaySystemSound(1001)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { successShown = true }
            onSuccess()
        }
        scene = s
        return s
    }
}

// MARK: - SpriteKit Scene

final class TrashScene: SKScene, SKPhysicsContactDelegate {

    var stickyUIColor: UIColor = .systemYellow
    var onSuccess: (() -> Void)?

    private enum Cat {
        static let paper:  UInt32 = 1 << 0
        static let trash:  UInt32 = 1 << 1
        static let floor:  UInt32 = 1 << 2
        static let sensor: UInt32 = 1 << 3
    }

    private var paper: SKShapeNode!
    private var isHeld = false
    private var isThrown = false
    private var didScore = false

    private var lastTouchPos = CGPoint.zero
    private var lastTouchTime: TimeInterval = 0
    private var flickVelocity = CGVector.zero

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        physicsWorld.contactDelegate = self
        setupBoundaries()
        setupTrashCan()
        setupPaper()
    }

    private func setupBoundaries() {
        let floor = SKNode()
        floor.position = CGPoint(x: size.width / 2, y: 8)
        let floorBody = SKPhysicsBody(
            rectangleOf: CGSize(width: size.width * 2, height: 16))
        floorBody.isDynamic = false
        floorBody.restitution = 0.3
        floorBody.categoryBitMask = Cat.floor
        floorBody.collisionBitMask = Cat.paper
        floor.physicsBody = floorBody
        addChild(floor)

        for xFrac: CGFloat in [-0.1, 1.1] {
            let wall = SKNode()
            wall.position = CGPoint(x: size.width * xFrac, y: size.height / 2)
            let wb = SKPhysicsBody(
                rectangleOf: CGSize(width: 8, height: size.height * 2))
            wb.isDynamic = false
            wb.categoryBitMask = Cat.floor
            wb.collisionBitMask = Cat.paper
            wall.physicsBody = wb
            addChild(wall)
        }
    }

    private func setupTrashCan() {
        let cx = size.width / 2
        let cy: CGFloat = 100
        let w: CGFloat = 100
        let h: CGFloat = 110
        let rim: CGFloat = 6

        // 底面
        addChild(edgeNode(from: CGPoint(x: cx - w/2, y: cy),
                          to:   CGPoint(x: cx + w/2, y: cy)))
        // 左壁
        addChild(edgeNode(from: CGPoint(x: cx - w/2 - rim, y: cy + h),
                          to:   CGPoint(x: cx - w/2, y: cy)))
        // 右壁
        addChild(edgeNode(from: CGPoint(x: cx + w/2 + rim, y: cy + h),
                          to:   CGPoint(x: cx + w/2, y: cy)))

        // 見た目
        let can = SKShapeNode()
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: cx - w/2 - rim, y: cy + h))
        path.addLine(to: CGPoint(x: cx - w/2, y: cy))
        path.addLine(to: CGPoint(x: cx + w/2, y: cy))
        path.addLine(to: CGPoint(x: cx + w/2 + rim, y: cy + h))
        can.path = path
        can.strokeColor = UIColor(white: 0.6, alpha: 1)
        can.lineWidth = rim
        can.lineCap = .round
        addChild(can)

        let label = SKLabelNode(text: "🗑️")
        label.fontSize = 28
        label.position = CGPoint(x: cx, y: cy + h + 8)
        addChild(label)

        // センサー（コリジョンなし・コンタクトのみ）
        let sensor = SKNode()
        sensor.position = CGPoint(x: cx, y: cy + h/2)
        let sb = SKPhysicsBody(rectangleOf: CGSize(width: w - 12, height: h - 16))
        sb.isDynamic = false
        sb.categoryBitMask = Cat.sensor
        sb.collisionBitMask = 0          // 物理衝突なし（センサー動作）
        sb.contactTestBitMask = Cat.paper
        sensor.physicsBody = sb
        addChild(sensor)
    }

    private func edgeNode(from: CGPoint, to: CGPoint) -> SKNode {
        let n = SKNode()
        let b = SKPhysicsBody(edgeFrom: from, to: to)
        b.isDynamic = false
        b.restitution = 0.5
        b.friction = 0.3
        b.categoryBitMask = Cat.trash
        b.collisionBitMask = Cat.paper
        n.physicsBody = b
        return n
    }

    private func setupPaper() {
        let r: CGFloat = 26
        paper = SKShapeNode(circleOfRadius: r)
        paper.fillColor = stickyUIColor
        paper.strokeColor = stickyUIColor.withAlphaComponent(0.5)
        paper.lineWidth = 2
        paper.position = CGPoint(x: size.width / 2, y: size.height * 0.6)

        let wrinkle = SKShapeNode(circleOfRadius: r * 0.35)
        wrinkle.fillColor = stickyUIColor.withAlphaComponent(0.55)
        wrinkle.strokeColor = .clear
        wrinkle.position = CGPoint(x: -r * 0.3, y: r * 0.25)
        paper.addChild(wrinkle)

        let body = SKPhysicsBody(circleOfRadius: r)
        body.isDynamic = false
        body.restitution = 0.35
        body.friction = 0.4
        body.mass = 0.08
        body.linearDamping = 0.15
        body.categoryBitMask = Cat.paper
        body.contactTestBitMask = Cat.sensor
        body.collisionBitMask = Cat.trash | Cat.floor
        paper.physicsBody = body
        addChild(paper)

        let hint = SKLabelNode(text: "持ち上げてフリック →  🗑️")
        hint.fontSize = 13
        hint.fontColor = UIColor(white: 1, alpha: 0.4)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.6 - 52)
        hint.name = "hint"
        addChild(hint)
    }

    // MARK: - タッチ

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        if paper.frame.insetBy(dx: -24, dy: -24).contains(loc), !isThrown {
            isHeld = true
            paper.physicsBody?.isDynamic = false
            lastTouchPos = loc
            lastTouchTime = touch.timestamp
            flickVelocity = .zero
            childNode(withName: "hint")?.removeFromParent()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isHeld else { return }
        let loc = touch.location(in: self)
        let dt = touch.timestamp - lastTouchTime
        if dt > 0.001 {
            flickVelocity = CGVector(
                dx: (loc.x - lastTouchPos.x) / CGFloat(dt),
                dy: (loc.y - lastTouchPos.y) / CGFloat(dt))
        }
        paper.position = loc
        lastTouchPos = loc
        lastTouchTime = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isHeld else { return }
        isHeld = false
        isThrown = true
        paper.physicsBody?.isDynamic = true
        let scale: CGFloat = 0.85
        paper.physicsBody?.velocity = CGVector(
            dx: flickVelocity.dx * scale,
            dy: flickVelocity.dy * scale)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - 衝突検知（センサー）

    func didBegin(_ contact: SKPhysicsContact) {
        guard !didScore else { return }
        let cats = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard cats == (Cat.paper | Cat.sensor) else { return }
        guard let vel = paper.physicsBody?.velocity, vel.dy < 30 else { return }
        didScore = true

        let pop = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.08),
            SKAction.scale(to: 0, duration: 0.25)
        ])
        paper.run(pop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onSuccess?()
        }
    }

    // MARK: - 床に落ちたら拾い直せるようにリセット

    override func update(_ currentTime: TimeInterval) {
        guard isThrown, !isHeld, !didScore, paper.position.y < 55 else { return }
        isThrown = false
        paper.physicsBody?.isDynamic = false
        paper.physicsBody?.velocity = .zero
        paper.physicsBody?.angularVelocity = 0
        let dest = CGPoint(x: size.width / 2, y: size.height * 0.55)
        paper.run(.move(to: dest, duration: 0.4))
        spawnRetryHint()
    }

    private func spawnRetryHint() {
        childNode(withName: "retryHint")?.removeFromParent()
        let lbl = SKLabelNode(text: "もう一度！")
        lbl.fontSize = 14
        lbl.fontColor = UIColor(white: 1, alpha: 0.5)
        lbl.position = CGPoint(x: size.width / 2, y: size.height * 0.55 - 52)
        lbl.name = "retryHint"
        addChild(lbl)
        lbl.run(.sequence([.wait(forDuration: 1.5), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }
}
