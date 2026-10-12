import Capacitor
import UIKit

/// Keep Capacitor's existing scene lifecycle and plugins; register only in-repo additions.
@objc(OpenGymBridgeViewController)
final class OpenGymBridgeViewController: CAPBridgeViewController {
    private let appleShell = AppleShellPlugin()

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(appleShell)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        appleShell.publishEnvironment()
    }
}
