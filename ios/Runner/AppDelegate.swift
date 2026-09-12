import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var privacyEnabled = true
  private var flutterForegroundReady = false
  private var privacyCover: UIView?
  private var privacyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      privacyChannel = FlutterMethodChannel(
        name: "zremote/privacy", binaryMessenger: controller.binaryMessenger)
      privacyChannel?.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setScreenPrivacy" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let arguments = call.arguments as? [String: Any],
          let enabled = arguments["enabled"] as? Bool,
          let foreground = arguments["foreground"] as? Bool
        else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        self?.privacyEnabled = enabled
        self?.flutterForegroundReady = foreground
        self?.updatePrivacyCover()
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    flutterForegroundReady = false
    showPrivacyCover()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    updatePrivacyCover()
  }

  private func updatePrivacyCover() {
    if !privacyEnabled ||
      (UIApplication.shared.applicationState == .active && flutterForegroundReady) {
      privacyCover?.removeFromSuperview()
      privacyCover = nil
    } else if UIApplication.shared.applicationState != .active {
      showPrivacyCover()
    }
  }

  private func showPrivacyCover() {
    guard privacyEnabled, privacyCover == nil, let window = window else { return }
    window.endEditing(true)
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .black
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.accessibilityElementsHidden = true
    window.addSubview(cover)
    privacyCover = cover
  }
}
