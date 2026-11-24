import Flutter
import UIKit

/// Clipboard images and statement files, plus files another app opens in
/// LiveNow (share sheet / "Open in"). The delegate methods below match
/// FlutterPlugin.h (`application:openURL:options:`) and
/// FlutterSceneLifeCycle.h (`scene:willConnectToSession:options:`,
/// `scene:openURLContexts:`).
@objc(LivenowClipboardPlugin)
public class LivenowClipboardPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private static let maxFileBytes = 5 * 1024 * 1024
  private static let statementExtensions: Set<String> = ["csv", "xlsx", "xls"]
  private static let statementTypes: [(uti: String, ext: String)] = [
    ("public.comma-separated-values-text", "csv"),
    ("public.delimited-values-text", "csv"),
    ("org.openxmlformats.spreadsheetml.sheet", "xlsx"),
    ("com.microsoft.excel.xls", "xls"),
  ]

  private var channel: FlutterMethodChannel?
  private var incoming: (name: String, bytes: Data)?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "livenow_clipboard", binaryMessenger: registrar.messenger())
    let instance = LivenowClipboardPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImages":
      result(UIPasteboard.general.hasImages)
    case "images":
      result(images())
    case "hasFiles":
      result(hasFiles())
    case "files":
      result(files())
    case "takeIncomingFile":
      if let file = incoming {
        incoming = nil
        result(["name": file.name, "bytes": FlutterStandardTypedData(bytes: file.bytes)])
      } else {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Open in / share (application delegate)

  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return take([url])
  }

  // MARK: - Open in / share (scene delegate)

  public func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return take(contexts.map { $0.url })
  }

  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return take(URLContexts.map { $0.url })
  }

  /// Keeps the first statement file among [urls] and tells Dart. True only
  /// when one was handled.
  private func take(_ urls: [URL]) -> Bool {
    for url in urls where url.isFileURL {
      guard let file = readStatement(url) else { continue }
      incoming = file
      channel?.invokeMethod("incomingFile", arguments: nil)
      return true
    }
    return false
  }

  /// A csv/xlsx/xls file read with security-scoped access, at most 5 MB.
  private func readStatement(_ url: URL) -> (name: String, bytes: Data)? {
    guard LivenowClipboardPlugin.statementExtensions.contains(url.pathExtension.lowercased()) else {
      return nil
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
       size > LivenowClipboardPlugin.maxFileBytes {
      return nil
    }
    guard let data = try? Data(contentsOf: url), data.count <= LivenowClipboardPlugin.maxFileBytes else {
      return nil
    }
    return (url.lastPathComponent, data)
  }

  // MARK: - Clipboard files

  /// Types only, no content: iOS shows no "Allow Paste" prompt.
  private func hasFiles() -> Bool {
    let known = Set(LivenowClipboardPlugin.statementTypes.map { $0.uti } + ["public.file-url"])
    return UIPasteboard.general.types.contains { known.contains($0) }
  }

  private func files() -> [[String: Any]] {
    let pb = UIPasteboard.general
    var out: [[String: Any]] = []
    for i in 0..<pb.numberOfItems {
      let set = IndexSet(integer: i)
      let types = pb.types(forItemSet: set)?.first ?? []
      var found = false
      for t in LivenowClipboardPlugin.statementTypes where types.contains(t.uti) {
        if let data = pb.data(forPasteboardType: t.uti, inItemSet: set)?.first,
           data.count <= LivenowClipboardPlugin.maxFileBytes {
          out.append(["name": "statement.\(t.ext)", "bytes": FlutterStandardTypedData(bytes: data)])
          found = true
          break
        }
      }
      if found { continue }
      if types.contains("public.file-url"),
         let raw = pb.data(forPasteboardType: "public.file-url", inItemSet: set)?.first,
         let url = URL(dataRepresentation: raw, relativeTo: nil),
         let file = readStatement(url) {
        out.append(["name": file.name, "bytes": FlutterStandardTypedData(bytes: file.bytes)])
      }
    }
    return out
  }

  /// One entry per clipboard item that holds an image: JPEG/PNG bytes as they
  /// were copied, anything else (HEIC, a bare UIImage) re-encoded as JPEG.
  private func images() -> [FlutterStandardTypedData] {
    let pb = UIPasteboard.general
    var out: [FlutterStandardTypedData] = []
    for i in 0..<pb.numberOfItems {
      let set = IndexSet(integer: i)
      if let data = raw(pb, set) {
        out.append(FlutterStandardTypedData(bytes: data))
        continue
      }
      if let data = converted(pb, set) {
        out.append(FlutterStandardTypedData(bytes: data))
      }
    }
    return out
  }

  private func raw(_ pb: UIPasteboard, _ set: IndexSet) -> Data? {
    for type in ["public.jpeg", "public.png"] {
      if let data = pb.data(forPasteboardType: type, inItemSet: set)?.first {
        return data
      }
    }
    return nil
  }

  private func converted(_ pb: UIPasteboard, _ set: IndexSet) -> Data? {
    let types = pb.types(forItemSet: set)?.first ?? []
    for type in types {
      guard let data = pb.data(forPasteboardType: type, inItemSet: set)?.first,
            let image = UIImage(data: data) else { continue }
      if let jpeg = image.jpegData(compressionQuality: 0.92) { return jpeg }
    }
    if let values = pb.values(forPasteboardType: "public.image", inItemSet: set),
       let image = values.first as? UIImage,
       let jpeg = image.jpegData(compressionQuality: 0.92) {
      return jpeg
    }
    return nil
  }
}
