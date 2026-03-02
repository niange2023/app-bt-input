class DeviceInfo {
  const DeviceInfo({
    required this.name,
    required this.address,
    required this.signalStrength,
  });

  // TODO: Add BLE metadata fields if needed by scan/connect UX.
  final String name;
  final String address;
  final int signalStrength;
}
