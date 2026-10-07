# graphx_connect_nearby example

Permanent Android/iOS acceptance app for the Nearby transport.

Use two physical devices with Bluetooth and Wi-Fi enabled:

```bash
cd packages/graphx_connect_nearby/example
flutter run -d <device-a>
flutter run -d <device-b>
```

On one device tap **HOST**, on the other tap **JOIN**. Once connected, tap **SEND** on either side. The peer must show `RX 1,2,3,4`.

The example uses the stable service ID:

```text
com.roipeker.graphx.connect.nearby.example
```

Its iOS `Info.plist` already contains the required Bluetooth, Local Network and Bonjour declarations. Access Wi-Fi Information / Hotspot Configuration are not part of the baseline example; add them only when the app uses the corresponding Wi-Fi information or hotspot upgrade path.
