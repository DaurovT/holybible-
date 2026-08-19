import CryptoKit
import DeviceCheck
import Flutter
import UIKit

/// Мост к App Attest.
///
/// Ключ заводится в защищённом элементе устройства и наружу не выходит: сюда
/// возвращается только его идентификатор, заверение от Apple и подписи. Всё
/// остальное — дело сервера, он и решает, верить ли этому устройству.
///
/// Данные клиента, которые подписываются, — это челлендж сервера как есть;
/// хеш считаем здесь, чтобы на стороне Dart не заводить ещё одну библиотеку.
final class AppAttestBridge: NSObject {
  static let channelName = "holybible/app_attest"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let bridge = AppAttestBridge()
    channel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }
  }

  private let service = DCAppAttestService.shared

  private func clientDataHash(_ challenge: String) -> Data {
    Data(SHA256.hash(data: Data(challenge.utf8)))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "isSupported":
      // На симуляторе и на старых устройствах App Attest недоступен —
      // приложение должно уметь это пережить, а не показать ошибку.
      result(service.isSupported)

    case "generateKey":
      service.generateKey { keyId, error in
        if let keyId {
          result(keyId)
        } else {
          result(Self.error("generateKey", error))
        }
      }

    case "attestKey":
      guard let keyId = args["keyId"] as? String,
            let challenge = args["challenge"] as? String else {
        result(Self.badArgs)
        return
      }
      service.attestKey(keyId, clientDataHash: clientDataHash(challenge)) { data, error in
        if let data {
          result(data.base64EncodedString())
        } else {
          result(Self.error("attestKey", error))
        }
      }

    case "generateAssertion":
      guard let keyId = args["keyId"] as? String,
            let challenge = args["challenge"] as? String else {
        result(Self.badArgs)
        return
      }
      service.generateAssertion(keyId, clientDataHash: clientDataHash(challenge)) { data, error in
        if let data {
          result(data.base64EncodedString())
        } else {
          result(Self.error("generateAssertion", error))
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var badArgs: FlutterError {
    FlutterError(code: "bad_args", message: "Не хватает аргументов", details: nil)
  }

  private static func error(_ method: String, _ error: Error?) -> FlutterError {
    FlutterError(code: "app_attest",
                 message: error?.localizedDescription ?? "\(method): без причины",
                 details: (error as NSError?)?.code)
  }
}
