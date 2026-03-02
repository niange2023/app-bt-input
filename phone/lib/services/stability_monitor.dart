import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

class StabilitySnapshot {
  const StabilitySnapshot({
    required this.sessionDuration,
    required this.totalCharsSent,
    required this.totalBleBytesSent,
    required this.blePacketsSent,
    required this.memoryUsageBytes,
    required this.reconnectionCount,
    required this.bleErrorCount,
  });

  final Duration sessionDuration;
  final int totalCharsSent;
  final int totalBleBytesSent;
  final int blePacketsSent;
  final int memoryUsageBytes;
  final int reconnectionCount;
  final int bleErrorCount;

  StabilitySnapshot copyWith({
    Duration? sessionDuration,
    int? totalCharsSent,
    int? totalBleBytesSent,
    int? blePacketsSent,
    int? memoryUsageBytes,
    int? reconnectionCount,
    int? bleErrorCount,
  }) {
    return StabilitySnapshot(
      sessionDuration: sessionDuration ?? this.sessionDuration,
      totalCharsSent: totalCharsSent ?? this.totalCharsSent,
      totalBleBytesSent: totalBleBytesSent ?? this.totalBleBytesSent,
      blePacketsSent: blePacketsSent ?? this.blePacketsSent,
      memoryUsageBytes: memoryUsageBytes ?? this.memoryUsageBytes,
      reconnectionCount: reconnectionCount ?? this.reconnectionCount,
      bleErrorCount: bleErrorCount ?? this.bleErrorCount,
    );
  }
}

class StabilityMonitor {
  StabilityMonitor._();

  static final StabilityMonitor instance = StabilityMonitor._();

  final DateTime _sessionStart = DateTime.now();
  final ValueNotifier<StabilitySnapshot> snapshot = ValueNotifier<StabilitySnapshot>(
    const StabilitySnapshot(
      sessionDuration: Duration.zero,
      totalCharsSent: 0,
      totalBleBytesSent: 0,
      blePacketsSent: 0,
      memoryUsageBytes: 0,
      reconnectionCount: 0,
      bleErrorCount: 0,
    ),
  );

  Timer? _memoryTimer;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }

    _started = true;
    _sampleMemory();
    _memoryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sampleMemory());
  }

  void recordCharsSent(int chars) {
    if (chars <= 0) {
      return;
    }
    final next = snapshot.value.copyWith(
      totalCharsSent: snapshot.value.totalCharsSent + chars,
      sessionDuration: DateTime.now().difference(_sessionStart),
    );
    snapshot.value = next;
  }

  void recordBlePacket(int bytes) {
    final next = snapshot.value.copyWith(
      totalBleBytesSent: snapshot.value.totalBleBytesSent + (bytes > 0 ? bytes : 0),
      blePacketsSent: snapshot.value.blePacketsSent + 1,
      sessionDuration: DateTime.now().difference(_sessionStart),
    );
    snapshot.value = next;
  }

  void recordReconnect() {
    snapshot.value = snapshot.value.copyWith(
      reconnectionCount: snapshot.value.reconnectionCount + 1,
      sessionDuration: DateTime.now().difference(_sessionStart),
    );
    Logger.debug('reconnection event tracked: ${snapshot.value.reconnectionCount}');
  }

  void recordBleError([String? reason]) {
    snapshot.value = snapshot.value.copyWith(
      bleErrorCount: snapshot.value.bleErrorCount + 1,
      sessionDuration: DateTime.now().difference(_sessionStart),
    );
    if (reason != null && reason.isNotEmpty) {
      Logger.debug('BLE error tracked: $reason');
    }
  }

  void _sampleMemory() {
    int memoryBytes = 0;
    try {
      memoryBytes = ProcessInfo.currentRss;
    } catch (_) {
      memoryBytes = 0;
    }

    snapshot.value = snapshot.value.copyWith(
      memoryUsageBytes: memoryBytes,
      sessionDuration: DateTime.now().difference(_sessionStart),
    );

    Logger.debug('stability memory sample: ${memoryBytes ~/ 1024 ~/ 1024} MB');
  }

  void dispose() {
    _memoryTimer?.cancel();
    _memoryTimer = null;
    _started = false;
  }
}
