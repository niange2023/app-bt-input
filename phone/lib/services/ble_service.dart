import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/protocol.dart';
import '../models/text_delta.dart';
import 'stability_monitor.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// iOS BLE 兼容性说明：
/// 1) iOS 不允许应用主动开启蓝牙，系统会在首次访问蓝牙能力时弹出授权对话框。
/// 2) iOS 实际可用 MTU 常见上限约为 185 字节，本实现会在分包前进行上限保护。
/// 3) iOS 后台 BLE 能力受系统策略限制，需要在 Info.plist 配置 bluetooth-central/
///    bluetooth-peripheral Background Modes；即使如此，后台长时间传输仍可能被系统挂起。
/// 4) 当蓝牙被拒绝或受限时，应用记录日志并保持可恢复状态，由 UI 引导用户到系统设置授权。

enum ControlCommand {
  activate,
  deactivate,
  syncRequest,
  clear,
}

class BleService {
  BleService({Protocol? protocol}) : _protocol = protocol ?? Protocol();

  final Protocol _protocol;
  final StreamController<ControlCommand> _controlCommandController =
      StreamController<ControlCommand>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  dynamic _connectedDevice;
  dynamic _textCharacteristic;
  dynamic _controlCharacteristic;
  dynamic _statusCharacteristic;
  int _negotiatedMtu = 23;

  Stream<ControlCommand> get controlCommands => _controlCommandController.stream;
  Stream<bool> get connectionChanges => _connectionController.stream;

  Future<void> initializeAsync() async {
    Logger.debug('BleService.initializeAsync');
    StabilityMonitor.instance.start();

    await _prepareIosBleEnvironmentAsync();

    // flutter_blue_plus 在多数平台上主要提供 Central API。
    // 若 GATT Server（Peripheral）API 不可用，则采用回退策略：
    // 手机端作为 Central，PC 端作为 Peripheral，协议层保持一致。
    await _initializeCentralFallbackAsync();
  }

  Future<void> startAdvertisingAsync() async {
    // TODO: 在可用平台上启用 GATT Server + Advertising。
    Logger.debug('startAdvertisingAsync skipped: using central fallback mode');
  }

  Future<void> connectAsync(Object device) async {
    _connectedDevice = device;
    final dynamic dynamicDevice = device;
    try {
      await dynamicDevice.connect();
      Logger.debug('BLE connected');
    } catch (error) {
      Logger.debug('BLE connect failed: $error');
      rethrow;
    }
    _connectionController.add(true);

    await _negotiateMtuAsync();
    await _discoverAndBindCharacteristicsAsync();
  }

  Future<void> disconnectAsync() async {
    try {
      final dynamic device = _connectedDevice;
      if (device != null) {
        await device.disconnect();
      }
    } finally {
      _connectedDevice = null;
      _textCharacteristic = null;
      _controlCharacteristic = null;
      _statusCharacteristic = null;
      _connectionController.add(false);
    }
  }

  Future<void> sendDelta(TextDelta delta, int seq) async {
    try {
      final payload = _protocol.encode(delta, seq);
      Logger.debug('sendDelta seq=$seq payload=$payload');
      StabilityMonitor.instance.recordCharsSent(delta.text.length);
      await _notifyTextPayloadAsync(payload);
    } catch (error) {
      Logger.debug('sendDelta failed: $error');
      StabilityMonitor.instance.recordBleError('sendDelta failed');
      rethrow;
    }
  }

  Future<void> sendHeartbeat({required int batteryPercent, required String imeName}) async {
    try {
      final payload = _protocol.encodeHeartbeat(batteryPercent, imeName);
      Logger.debug('sendHeartbeat payload=$payload');
      final bytes = Uint8List.fromList(utf8.encode(payload));
      final status = _statusCharacteristic;
      if (status != null) {
        await status.write(bytes, withoutResponse: true);
      }
    } catch (error) {
      Logger.debug('sendHeartbeat failed: $error');
      StabilityMonitor.instance.recordBleError('sendHeartbeat failed');
    }
  }

  Future<void> sendSpecialKey(String keyName, int seq) async {
    try {
      final payload = _protocol.encodeSpecialKey(seq, keyName);
      Logger.debug('sendSpecialKey seq=$seq key=$keyName payload=$payload');
      await _notifyTextPayloadAsync(payload);
    } catch (error) {
      Logger.debug('sendSpecialKey failed: $error');
      StabilityMonitor.instance.recordBleError('sendSpecialKey failed');
      rethrow;
    }
  }

  Future<void> _initializeCentralFallbackAsync() async {
    Logger.debug('Initializing BLE in central fallback mode');
  }

  Future<void> _prepareIosBleEnvironmentAsync() async {
    if (!Platform.isIOS) {
      return;
    }

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        Logger.debug('iOS BLE not supported on this device');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);

      if (adapterState == BluetoothAdapterState.unauthorized) {
        Logger.debug('iOS Bluetooth permission unauthorized, please grant permission in Settings');
      } else if (adapterState == BluetoothAdapterState.off) {
        Logger.debug('iOS Bluetooth is off, waiting for user to enable it in system settings');
      } else {
        Logger.debug('iOS Bluetooth adapter state: $adapterState');
      }
    } catch (error) {
      Logger.debug('iOS BLE environment preparation failed: $error');
    }
  }

  Future<void> _negotiateMtuAsync() async {
    final dynamic device = _connectedDevice;
    if (device == null) {
      return;
    }
    try {
      final int mtu = await device.requestMtu(512) as int;
      _negotiatedMtu = Platform.isIOS ? (mtu > 185 ? 185 : mtu) : mtu;
      Logger.debug('Negotiated MTU: $_negotiatedMtu');
    } catch (_) {
      _negotiatedMtu = Platform.isIOS ? 185 : 23;
      Logger.debug('MTU negotiation failed, fallback to $_negotiatedMtu');
    }
  }

  Future<void> _discoverAndBindCharacteristicsAsync() async {
    final dynamic device = _connectedDevice;
    if (device == null) {
      return;
    }

    final services = await device.discoverServices();
    for (final service in services) {
      final String serviceUuid = service.uuid.toString().toUpperCase();
      if (serviceUuid != Constants.bleServiceUuid) {
        continue;
      }

      for (final characteristic in service.characteristics) {
        final String uuid = characteristic.uuid.toString().toUpperCase();
        if (uuid == Constants.textCharacteristicUuid) {
          _textCharacteristic = characteristic;
        } else if (uuid == Constants.controlCharacteristicUuid) {
          _controlCharacteristic = characteristic;
          await _bindControlCharacteristicAsync(characteristic);
        } else if (uuid == Constants.statusCharacteristicUuid) {
          _statusCharacteristic = characteristic;
        }
      }
    }
  }

  Future<void> _bindControlCharacteristicAsync(dynamic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.onValueReceived.listen(_onControlDataReceived);
    } catch (_) {
      Logger.debug('Control characteristic notify not available in current mode');
    }
  }

  void _onControlDataReceived(dynamic rawBytes) {
    try {
      final data = jsonDecode(utf8.decode((rawBytes as List<int>))) as Map<String, dynamic>;
      final int? type = data['t'] as int?;
      if (type == Constants.msgActivate) {
        _controlCommandController.add(ControlCommand.activate);
      } else if (type == Constants.msgDeactivate) {
        _controlCommandController.add(ControlCommand.deactivate);
      } else if (type == Constants.msgSyncRequest) {
        _controlCommandController.add(ControlCommand.syncRequest);
      } else if (type == Constants.msgClear) {
        _controlCommandController.add(ControlCommand.clear);
      }
    } catch (_) {
      Logger.debug('Failed to parse control command payload');
    }
  }

  Future<void> _notifyTextPayloadAsync(String payload) async {
    final textCharacteristic = _textCharacteristic;
    if (textCharacteristic == null) {
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode(payload));
    final chunks = _fragment(bytes, _negotiatedMtu);
    for (final chunk in chunks) {
      try {
        await textCharacteristic.write(chunk, withoutResponse: true);
        StabilityMonitor.instance.recordBlePacket(chunk.length);
      } catch (error) {
        Logger.debug('BLE write failed during chunk send: $error');
        StabilityMonitor.instance.recordBleError('chunk write failed');
        rethrow;
      }
    }
  }

  List<Uint8List> _fragment(Uint8List message, int mtu) {
    final payloadSize = (mtu - 3).clamp(1, mtu);
    if (message.length <= payloadSize) {
      return <Uint8List>[message];
    }

    final total = (message.length / payloadSize).ceil();
    final msgId = DateTime.now().millisecond & 0xFF;
    final chunks = <Uint8List>[];

    for (int seq = 0; seq < total; seq++) {
      final start = seq * payloadSize;
      final end = (start + payloadSize) > message.length ? message.length : (start + payloadSize);
      final body = message.sublist(start, end);
      final isLast = seq == total - 1;

      final header = Uint8List.fromList(<int>[
        msgId,
        ((seq & 0x0F) << 4) | (isLast ? 0x01 : 0x00),
        total & 0xFF,
      ]);

      chunks.add(Uint8List.fromList(<int>[...header, ...body]));
    }

    return chunks;
  }

  Future<void> disposeAsync() async {
    await _controlCommandController.close();
    await _connectionController.close();
  }
}
