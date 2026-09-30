import UIKit

/// UI tests only (`DEVREPLY_SHEET_PROBE=1`): watches the presented sheet every frame and shows, in a tiny
/// window above everything, how far it has moved from where it settled after opening:
/// "sheet down <pt> up <pt>" (a new sheet starts again from 0). A drag that the sheet takes instead of the
/// chat shows up here even though the sheet springs back when the finger lifts. Never used otherwise.
@MainActor
final class SheetProbe: NSObject {
    static let shared = SheetProbe()
    private var window: UIWindow?
    private let button = UIButton(type: .system)
    private var rest: CGFloat?
    private weak var sheet: UIViewController?
    private var last: CGFloat?
    private var stableFrames = 0
    private var down: CGFloat = 0
    private var up: CGFloat = 0

    static func startIfAsked() {
        guard ProcessInfo.processInfo.environment["DEVREPLY_SHEET_PROBE"] == "1" else { return }
        // The scene isn't connected yet at App.init.
        DispatchQueue.main.async { shared.start() }
    }

    private func start() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.start() }
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 220, height: 22)
        window.windowLevel = .alert + 1
        let root = UIViewController()
        button.frame = window.bounds
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        button.accessibilityIdentifier = "sheetProbe"
        root.view.addSubview(button)
        window.rootViewController = root
        window.isHidden = false
        self.window = window
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        render()
    }

    /// The topmost presented sheet and its top, in screen points.
    private var sheetTop: (UIViewController, CGFloat)? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for candidate in scenes.flatMap(\.windows) where candidate !== window && !candidate.isHidden {
            var top = candidate.rootViewController
            var presented: UIViewController?
            while let next = top?.presentedViewController { presented = next; top = next }
            if let view = presented?.view, let host = view.window {
                return (presented!, view.convert(CGPoint.zero, to: host).y)
            }
        }
        return nil
    }

    @objc private func tick() {
        guard let (presented, y) = sheetTop else { return }
        if presented !== sheet {
            // A new sheet: wait until it has settled (half a second without moving), then measure from there.
            sheet = presented
            rest = nil
            (down, up, stableFrames, last) = (0, 0, 0, nil)
            render()
        }
        guard let rest else {
            stableFrames = last.map { abs($0 - y) < 0.5 } == true ? stableFrames + 1 : 0
            last = y
            if stableFrames >= 30 { self.rest = y; render() }
            return
        }
        let before = (down, up)
        down = max(down, y - rest)
        up = max(up, rest - y)
        if before != (down, up) { render() }
    }

    private func render() {
        let title = rest == nil ? "sheet unset" : "sheet down \(Int(down.rounded())) up \(Int(up.rounded()))"
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
    }
}
