import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// `LiveNow --hub ...`: the always-on sync hub. It has no UI, so it gets no
  /// Dock icon and its window is never shown (the Dart side never calls
  /// runApp). Mirrors windows/runner/flutter_window.cpp.
  private static let isHub = ProcessInfo.processInfo.arguments.contains("--hub")

  override func awakeFromNib() {
    if MainFlutterWindow.isHub {
      NSApp.setActivationPolicy(.prohibited)
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Dart asks for the window to come forward when a notification is tapped.
    let channel = FlutterMethodChannel(
      name: "io.livenow/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "activate" {
        NSApp.activate(ignoringOtherApps: true)
        self?.makeKeyAndOrderFront(nil)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()

    if MainFlutterWindow.isHub {
      self.orderOut(nil)
    }
  }
}
