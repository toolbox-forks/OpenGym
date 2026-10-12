import Capacitor
import UIKit

@objc(AppleShellPlugin)
final class AppleShellPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "AppleShellPlugin"
    let jsName = "AppleShell"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "environment", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "haptic", returnType: CAPPluginReturnPromise)
    ]
    private var observers: [NSObjectProtocol] = []
    private var keyboardHeight: CGFloat = 0

    override func load() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                             object: nil, queue: .main) { [weak self] note in
            guard let self, let view = self.bridge?.viewController?.view,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // Convert from screen to this window/view (rotation and scene-safe).
            guard let window = view.window else { return }
            let inWindow = window.convert(frame, from: window.screen.coordinateSpace)
            let local = view.convert(inWindow, from: window)
            self.keyboardHeight = ShellGeometry.keyboardOcclusion(bounds: view.bounds, keyboard: local)
            self.publishEnvironment()
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.keyboardHeight = 0
            self?.publishEnvironment()
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func values() -> [String: Any] {
        let insets = bridge?.viewController?.view.safeAreaInsets ?? .zero
        return ["top": Double(insets.top), "bottom": Double(insets.bottom),
                "keyboardHeight": Double(keyboardHeight)]
    }

    func publishEnvironment() {
        notifyListeners("environmentChanged", data: values())
    }

    @objc func environment(_ call: CAPPluginCall) {
        DispatchQueue.main.async { call.resolve(self.values()) }
    }

    @objc func haptic(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            switch call.getString("kind") ?? "light" {
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "selection": UISelectionFeedbackGenerator().selectionChanged()
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            call.resolve()
        }
    }
}
