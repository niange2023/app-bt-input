import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/protocol.dart';
import '../models/text_delta.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

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
      await _notifyTextPayloadAsync(payload);
    } catch (error) {
      Logger.debug('sendDelta failed: $error');
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
    }
  }

  Future<void> sendSpecialKey(String keyName, int seq) async {
    try {
      final payload = _protocol.encodeSpecialKey(seq, keyName);
      Logger.debug('sendSpecialKey seq=$seq key=$keyName payload=$payload');
      await _notifyTextPayloadAsync(payload);
    } catch (error) {
      Logger.debug('sendSpecialKey failed: $error');
      rethrow;
    }
  }

  Future<void> _initializeCentralFallbackAsync() async {
    Logger.debug('Initializing BLE in central fallback mode');
  }

  Future<void> _negotiateMtuAsync() async {
    final dynamic device = _connectedDevice;
    if (device == null) {
      return;
    }
    try {
      final int mtu = await device.requestMtu(512) as int;
      _negotiatedMtu = mtu;
      Logger.debug('Negotiated MTU: $_negotiatedMtu');
    } catch (_) {
      _negotiatedMtu = 23;
      Logger.debug('MTU negotiation failed, fallback to default 23');
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
      } catch (error) {
        Logger.debug('BLE write failed during chunk send: $error');
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
