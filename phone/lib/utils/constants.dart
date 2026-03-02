class Constants {
  static const String bleServiceUuid = '0000FFF0-0000-1000-8000-00805F9B34FB';
  static const String textCharacteristicUuid = '0000FFF1-0000-1000-8000-00805F9B34FB';
  static const String controlCharacteristicUuid = '0000FFF2-0000-1000-8000-00805F9B34FB';
  static const String statusCharacteristicUuid = '0000FFF3-0000-1000-8000-00805F9B34FB';

  static const int throttleWindowMs = 50;
  static const int autoClearThresholdChars = 500;
  static const int autoClearIdleTimeoutMs = 2000;
  static const int heartbeatIntervalMs = 5000;

  static const int msgTextDelta = 0x01;
  static const int msgTextFullSync = 0x02;
  static const int msgHeartbeat = 0x03;
  static const int msgInputStarted = 0x04;
  static const int msgInputStopped = 0x05;
  static const int msgSegmentComplete = 0x06;
  static const int msgSpecialKey = 0x07;

  static const int msgActivate = 0x81;
  static const int msgDeactivate = 0x82;
  static const int msgSyncRequest = 0x83;
  static const int msgClear = 0x84;
}
