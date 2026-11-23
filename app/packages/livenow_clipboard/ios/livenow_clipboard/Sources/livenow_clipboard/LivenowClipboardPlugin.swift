import Flutter
import UIKit

@objc(LivenowClipboardPlugin)
public class LivenowClipboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "livenow_clipboard", binaryMessenger: registrar.messenger())
    let instance = LivenowClipboardPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImages":
      result(UIPasteboard.general.hasImages)
    case "images":
      result(images())
    default:
      result(FlutterMethodNotImplemented)
    }
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
