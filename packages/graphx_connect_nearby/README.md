# graphx_connect_nearby

Google Nearby Connections transport for `graphx_connect` on Android and iOS.

```dart
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_nearby/graphx_connect_nearby.dart';

final connect = GConnect(name: 'Phone');
final nearby = connect.nearby(service: 'com.example.myapp');

final host = await nearby.host('Living Room');
// or: final discovery = await nearby.discover();
//     final session = await nearby.join(found.session);
```

The service ID must be stable and identical on both devices. A reverse-domain app ID is recommended. GraphX exposes only `GSession`/`GMessage`; BLE, Wi-Fi and Google Nearby SDK types stay internal.

## Android

The plugin uses `com.google.android.gms:play-services-nearby:19.5.0`, minSdk 24. Its manifest declares the required Bluetooth/Wi-Fi/location/local-network permissions and the plugin requests dangerous permissions before discovery/advertising. `ACCESS_WIFI_STATE` and `CHANGE_WIFI_STATE` are deliberately left uncapped because current P2P advertising on newer Android releases still checks them. No API key is required.

If permission is denied, the operation fails explicitly; Connect does not silently switch transport.

## iOS

Requires iOS 15+ and Flutter with Swift Package Manager support. The plugin pins Google's `NearbyConnections` Swift package itself.

Add to the app `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connect to nearby devices.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Connect to nearby devices.</string>
```

Also add the Bonjour service required for the exact service ID. The plugin derives it as the uppercase first 12 hex characters of SHA-256:

```text
_<HASH>._tcp
```

and validates the entry before starting Nearby. For example, generate it on macOS with:

```bash
SERVICE_ID='com.example.myapp'
printf %s "$SERVICE_ID" | shasum -a 256
```

Take the first 12 hex characters, uppercase them, and add `_<HASH>._tcp` under `NSBonjourServices`.

The baseline Bluetooth / local-network path does not require extra Xcode capabilities beyond the `Info.plist` declarations above. If your app needs Wi-Fi network information/state, enable **Access Wi-Fi Information**. The optional high-speed hotspot path additionally needs `NSLocationWhenInUseUsageDescription` and the **Hotspot Configuration** capability.

## Device acceptance

A permanent physical-device smoke app lives in `example/`. Run it on two Android/iOS devices, tap **HOST** on one and **JOIN** on the other, then use **SEND** to verify byte delivery. This is the canonical transport acceptance path; no temporary probe project or local package override is required.

## Current scope

Byte payloads, discovery, connection lifecycle and reconnect-compatible GraphX sessions are implemented. Nearby stream/file payloads are deliberately reserved for the future common byte-stream API. Pair verification currently auto-accepts for low-friction local sessions; do not use this mode for sensitive unauthenticated data until an explicit verification policy is exposed.
