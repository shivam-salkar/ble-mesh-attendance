# Mobile Client — BLE Mesh Attendance

Cross-platform mobile application for classroom attendance using an application-level BLE peer-to-peer relay.

## Flutter Version Requirement

- **Flutter SDK:** `>= 3.24.0` (Dart `>= 3.5.0`)
- Validated on Flutter 3.27.x+ / Dart 3.6.x+

Verify your installation:

```bash
flutter doctor
```

## How to Run

1. Change directory to the mobile app:
   ```bash
   cd apps/mobile
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the development app:
   ```bash
   flutter run
   ```

## Platform Setup

### Android Setup

- **Minimum SDK:** API 24 (Android 7.0) or higher (recommended API 26+ for BLE advertising/scanning stability).
- **Target SDK:** API 34+
- **Required Permissions (to be configured during BLE implementation):**
  - `BLUETOOTH_SCAN` (`android:usesPermissionFlags="neverForLocation"` if applicable)
  - `BLUETOOTH_ADVERTISE`
  - `BLUETOOTH_CONNECT`
  - `ACCESS_FINE_LOCATION` (for older Android versions)
  - Camera permissions (for future face verification)
- Configure permissions in `android/app/src/main/AndroidManifest.xml` when BLE packages are introduced.

### iOS Setup

- **Target iOS:** iOS 14.0 or higher.
- **Info.plist Keys (to be configured during BLE implementation):**
  - `NSBluetoothAlwaysUsageDescription`
  - `NSBluetoothPeripheralUsageDescription`
  - `NSCameraUsageDescription` (for future face verification)
  - Background Modes for BLE peripheral/central roles if needed.

## Future BLE Integration Note

- **Application-Level Relay:** The mobile client will participate in an application-level peer-to-peer relay over BLE (inspired by BitChat's decentralized multi-hop architecture).
- **Distinct from Bluetooth SIG Mesh:** This client does NOT use Bluetooth SIG Mesh profiles or ESP-BLE-MESH.
- **Protocol:** Custom attendance packet protocol (defined in `/protocol`) handling peer discovery, time-limited student tokens, message forwarding, hop limits (TTL), and gateway submission.
- **Face Verification:** An on-device face verification layer will be integrated in a subsequent phase prior to packet generation.
