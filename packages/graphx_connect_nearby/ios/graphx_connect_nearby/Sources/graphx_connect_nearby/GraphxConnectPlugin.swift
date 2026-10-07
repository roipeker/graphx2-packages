import CoreLocation
import CryptoKit
import Flutter
import Foundation
import NearbyConnections
import UIKit

public final class GraphxConnectPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannel = "graphx_connect/nearby/methods"
  private static let eventChannel = "graphx_connect/nearby/events"

  private var eventSink: FlutterEventSink?
  private var instances: [String: NearbyInstance] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = GraphxConnectPlugin()
    let methods = FlutterMethodChannel(
      name: methodChannel,
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: eventChannel,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(plugin, channel: methods)
    events.setStreamHandler(plugin)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_args", message: "Expected arguments.", details: nil))
      return
    }

    switch call.method {
    case "create":
      guard
        let id = arguments["instanceId"] as? String,
        let serviceID = arguments["serviceId"] as? String,
        let endpointName = arguments["endpointName"] as? String,
        !id.isEmpty, !serviceID.isEmpty, !endpointName.isEmpty
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Missing nearby instance configuration.",
            details: nil
          )
        )
        return
      }

      instances.removeValue(forKey: id)?.dispose()
      instances[id] = NearbyInstance(
        instanceID: id,
        serviceID: serviceID,
        endpointName: endpointName,
        emit: emit
      )
      result(nil)

    case "prepare":
      withInstance(arguments, result: result) { instance in
        instance.prepare(result: result)
      }

    case "startAdvertising":
      withInstance(arguments, result: result) { instance in
        guard let typed = arguments["context"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "bad_args", message: "Missing context.", details: nil))
          return
        }
        instance.startAdvertising(context: typed.data, result: result)
      }

    case "stopAdvertising":
      withInstance(arguments, result: result) { instance in
        instance.stopAdvertising()
        result(nil)
      }

    case "startDiscovery":
      withInstance(arguments, result: result) { instance in
        instance.startDiscovery(result: result)
      }

    case "stopDiscovery":
      withInstance(arguments, result: result) { instance in
        instance.stopDiscovery()
        result(nil)
      }

    case "requestConnection":
      withInstance(arguments, result: result) { instance in
        guard let endpointID = arguments["endpointId"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing endpointId.", details: nil))
          return
        }
        instance.requestConnection(to: endpointID, result: result)
      }

    case "send":
      withInstance(arguments, result: result) { instance in
        guard
          let endpointID = arguments["endpointId"] as? String,
          let typed = arguments["data"] as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "bad_args", message: "Missing send arguments.", details: nil))
          return
        }
        instance.send(typed.data, to: endpointID, result: result)
      }

    case "disconnect":
      withInstance(arguments, result: result) { instance in
        guard let endpointID = arguments["endpointId"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing endpointId.", details: nil))
          return
        }
        instance.disconnect(from: endpointID)
        result(nil)
      }

    case "dispose":
      guard let id = arguments["instanceId"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing instanceId.", details: nil))
        return
      }
      instances.removeValue(forKey: id)?.dispose()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func withInstance(
    _ arguments: [String: Any],
    result: @escaping FlutterResult,
    body: (NearbyInstance) -> Void
  ) {
    guard
      let id = arguments["instanceId"] as? String,
      let instance = instances[id]
    else {
      result(
        FlutterError(
          code: "unknown_instance",
          message: "Nearby instance is not active.",
          details: nil
        )
      )
      return
    }
    body(instance)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }
}

private final class NearbyInstance: NSObject {
  private let instanceID: String
  private let serviceID: String
  private let endpointName: String
  private let emitEvent: ([String: Any]) -> Void

  private let connectionManager: ConnectionManager
  private var advertiser: Advertiser?
  private var discoverer: Discoverer?
  private var locationManager: CLLocationManager?

  private var advertisedContext: Data?
  private var shouldAdvertise = false
  private var advertising = false
  private var discovering = false
  private var connectedEndpoints: Set<EndpointID> = []

  init(
    instanceID: String,
    serviceID: String,
    endpointName: String,
    emit: @escaping ([String: Any]) -> Void
  ) {
    self.instanceID = instanceID
    self.serviceID = serviceID
    self.endpointName = endpointName
    self.emitEvent = emit
    self.connectionManager = ConnectionManager(
      serviceID: serviceID,
      strategy: .pointToPoint
    )
    super.init()
    connectionManager.delegate = self
  }

  func prepare(result: @escaping FlutterResult) {
    guard let bluetooth = Bundle.main.object(
      forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription"
    ) as? String, !bluetooth.isEmpty else {
      result(
        setupError(
          "missing_bluetooth_usage",
          "Add NSBluetoothAlwaysUsageDescription to the app Info.plist."
        )
      )
      return
    }

    guard let localNetwork = Bundle.main.object(
      forInfoDictionaryKey: "NSLocalNetworkUsageDescription"
    ) as? String, !localNetwork.isEmpty else {
      result(
        setupError(
          "missing_local_network_usage",
          "Add NSLocalNetworkUsageDescription to the app Info.plist."
        )
      )
      return
    }

    let requiredBonjour = bonjourServiceType(for: serviceID)
    let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices")
      as? [String] ?? []
    guard services.contains(requiredBonjour) else {
      result(
        FlutterError(
          code: "missing_bonjour_service",
          message: "Add \(requiredBonjour) to NSBonjourServices for service ID \(serviceID).",
          details: requiredBonjour
        )
      )
      return
    }

    // Location is needed only when the host app opts into Nearby's high-speed
    // Wi-Fi Hotspot path. Request it when the app has declared the usage key.
    if let description = Bundle.main.object(
      forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"
    ) as? String, !description.isEmpty {
      let manager = locationManager ?? CLLocationManager()
      locationManager = manager
      if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
      }
    }

    result(nil)
  }

  func startAdvertising(context: Data, result: @escaping FlutterResult) {
    advertisedContext = context
    shouldAdvertise = true

    let advertiser = Advertiser(connectionManager: connectionManager)
    advertiser.delegate = self
    self.advertiser = advertiser

    advertiser.startAdvertising(using: context) { [weak self] error in
      DispatchQueue.main.async {
        if let error {
          self?.advertising = false
          result(
            FlutterError(
              code: "advertise_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          self?.advertising = true
          result(nil)
        }
      }
    }
  }

  func stopAdvertising() {
    shouldAdvertise = false
    advertisedContext = nil
    if advertising {
      advertiser?.stopAdvertising()
    }
    advertising = false
    advertiser = nil
  }

  func startDiscovery(result: @escaping FlutterResult) {
    let discoverer = Discoverer(connectionManager: connectionManager)
    discoverer.delegate = self
    self.discoverer = discoverer

    discoverer.startDiscovery { [weak self] error in
      DispatchQueue.main.async {
        if let error {
          self?.discovering = false
          result(
            FlutterError(
              code: "discovery_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          self?.discovering = true
          result(nil)
        }
      }
    }
  }

  func stopDiscovery() {
    if discovering {
      discoverer?.stopDiscovery()
    }
    discovering = false
    discoverer = nil
  }

  func requestConnection(to endpointID: EndpointID, result: @escaping FlutterResult) {
    guard let discoverer else {
      result(
        FlutterError(
          code: "not_discovering",
          message: "Nearby discovery is not active.",
          details: nil
        )
      )
      return
    }

    let context = Data(endpointName.utf8)
    discoverer.requestConnection(to: endpointID, using: context) { error in
      DispatchQueue.main.async {
        if let error {
          result(
            FlutterError(
              code: "connect_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(nil)
        }
      }
    }
  }

  func send(_ data: Data, to endpointID: EndpointID, result: @escaping FlutterResult) {
    _ = connectionManager.send(data, to: [endpointID]) { [weak self] error in
      DispatchQueue.main.async {
        if let error {
          self?.event(
            "error",
            endpointID: endpointID,
            extra: ["message": error.localizedDescription]
          )
          result(
            FlutterError(
              code: "send_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(nil)
        }
      }
    }
  }

  func disconnect(from endpointID: EndpointID) {
    connectionManager.disconnect(from: endpointID)
  }

  func dispose() {
    shouldAdvertise = false
    advertisedContext = nil
    if advertising {
      advertiser?.stopAdvertising()
    }
    if discovering {
      discoverer?.stopDiscovery()
    }
    advertising = false
    discovering = false
    advertiser = nil
    discoverer = nil

    for endpointID in connectedEndpoints {
      connectionManager.disconnect(from: endpointID)
    }
    connectedEndpoints.removeAll()
  }

  private func restartAdvertisingIfNeeded() {
    guard shouldAdvertise, !advertising, let context = advertisedContext else {
      return
    }

    let advertiser = Advertiser(connectionManager: connectionManager)
    advertiser.delegate = self
    self.advertiser = advertiser
    advertiser.startAdvertising(using: context) { [weak self] error in
      if let error {
        self?.event(
          "error",
          extra: ["message": error.localizedDescription]
        )
      } else {
        self?.advertising = true
      }
    }
  }

  private func event(
    _ type: String,
    endpointID: EndpointID? = nil,
    extra: [String: Any] = [:]
  ) {
    var event: [String: Any] = [
      "instanceId": instanceID,
      "type": type,
    ]
    if let endpointID {
      event["endpointId"] = endpointID
    }
    for (key, value) in extra {
      event[key] = value
    }
    emitEvent(event)
  }

  private func setupError(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func bonjourServiceType(for serviceID: String) -> String {
    let digest = SHA256.hash(data: Data(serviceID.utf8))
    let prefix = digest.prefix(6).map { String(format: "%02X", $0) }.joined()
    return "_\(prefix)._tcp"
  }
}

extension NearbyInstance: AdvertiserDelegate {
  func advertiser(
    _ advertiser: Advertiser,
    didReceiveConnectionRequestFrom endpointID: EndpointID,
    with context: Data,
    connectionRequestHandler: @escaping (Bool) -> Void
  ) {
    connectionRequestHandler(true)
  }
}

extension NearbyInstance: DiscovererDelegate {
  func discoverer(
    _ discoverer: Discoverer,
    didFind endpointID: EndpointID,
    with context: Data
  ) {
    event(
      "found",
      endpointID: endpointID,
      extra: ["context": FlutterStandardTypedData(bytes: context)]
    )
  }

  func discoverer(_ discoverer: Discoverer, didLose endpointID: EndpointID) {
    event("lost", endpointID: endpointID)
  }
}

extension NearbyInstance: ConnectionManagerDelegate {
  func connectionManager(
    _ connectionManager: ConnectionManager,
    didReceive verificationCode: String,
    from endpointID: EndpointID,
    verificationHandler: @escaping (Bool) -> Void
  ) {
    // GraphX Nearby defaults to frictionless pairing for transient game/tool
    // sessions. Exposing explicit human verification can be added later
    // without changing GSession.
    verificationHandler(true)
  }

  func connectionManager(
    _ connectionManager: ConnectionManager,
    didReceive data: Data,
    withID payloadID: PayloadID,
    from endpointID: EndpointID
  ) {
    event(
      "payload",
      endpointID: endpointID,
      extra: ["data": FlutterStandardTypedData(bytes: data)]
    )
  }

  func connectionManager(
    _ connectionManager: ConnectionManager,
    didReceive stream: InputStream,
    withID payloadID: PayloadID,
    from endpointID: EndpointID,
    cancellationToken token: CancellationToken
  ) {
    token.cancel()
    event(
      "error",
      endpointID: endpointID,
      extra: ["message": "Nearby streams are not enabled in graphx_connect yet."]
    )
  }

  func connectionManager(
    _ connectionManager: ConnectionManager,
    didStartReceivingResourceWithID payloadID: PayloadID,
    from endpointID: EndpointID,
    at localURL: URL,
    withName name: String,
    cancellationToken token: CancellationToken
  ) {
    token.cancel()
    event(
      "error",
      endpointID: endpointID,
      extra: ["message": "Nearby file payloads are not enabled in graphx_connect yet."]
    )
  }

  func connectionManager(
    _ connectionManager: ConnectionManager,
    didReceiveTransferUpdate update: TransferUpdate,
    from endpointID: EndpointID,
    forPayload payloadID: PayloadID
  ) {
    if case .failure = update {
      event(
        "error",
        endpointID: endpointID,
        extra: ["message": "Nearby payload transfer failed."]
      )
    }
  }

  func connectionManager(
    _ connectionManager: ConnectionManager,
    didChangeTo state: ConnectionState,
    for endpointID: EndpointID
  ) {
    switch state {
    case .connecting:
      break
    case .connected:
      connectedEndpoints.insert(endpointID)

      if discovering {
        discoverer?.stopDiscovery()
        discovering = false
      }
      if advertising {
        advertiser?.stopAdvertising()
        advertising = false
      }
      event("connected", endpointID: endpointID)

    case .disconnected:
      connectedEndpoints.remove(endpointID)
      event("disconnected", endpointID: endpointID)
      restartAdvertisingIfNeeded()

    case .rejected:
      connectedEndpoints.remove(endpointID)
      event(
        "connectionFailed",
        endpointID: endpointID,
        extra: ["message": "Nearby connection was rejected."]
      )

    @unknown default:
      event(
        "connectionFailed",
        endpointID: endpointID,
        extra: ["message": "Unknown Nearby connection state."]
      )
    }
  }
}
