import 'dart:async';

import '../models/connection_state.dart';
import '../utils/constants.dart';
import 'ble_service.dart';

class ConnectionManager {
  ConnectionManager({required BleService bleService}) : _bleService = bleService {
    _bleService.connectionChanges.listen((connected) {
      if (connected) {
        _updateState(ConnectionStateModel.connected);
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        _updateState(ConnectionStateModel.disconnected);
      }
    });
  }

  final BleService _bleService;
  final StreamController<ConnectionStateModel> _stateController =
      StreamController<ConnectionStateModel>.broadcast();

  ConnectionStateModel _currentState = ConnectionStateModel.disconnected;
  Timer? _heartbeatTimer;

  Stream<ConnectionStateModel> get stateStream => _stateController.stream;
  ConnectionStateModel get currentState => _currentState;

  Future<void> connect(Object device) async {
    _updateState(ConnectionStateModel.connecting);
    try {
      await _bleService.connectAsync(device);
    } catch (_) {
      _stopHeartbeat();
      _updateState(ConnectionStateModel.disconnected);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _stopHeartbeat();
    await _bleService.disconnectAsync();
    _updateState(ConnectionStateModel.disconnected);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: Constants.heartbeatIntervalMs),
      (_) {
        _bleService.sendHeartbeat(batteryPercent: 100, imeName: 'system');
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _updateState(ConnectionStateModel state) {
    _currentState = state;
    _stateController.add(state);
  }

  Future<void> disposeAsync() async {
    _stopHeartbeat();
    await _stateController.close();
  }
}
