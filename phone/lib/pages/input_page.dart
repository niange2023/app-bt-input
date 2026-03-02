import 'package:flutter/material.dart';

import 'dart:async';

import '../core/protocol.dart';
import '../core/throttle_sender.dart';
import '../models/connection_state.dart';
import '../services/ble_service.dart';
import '../services/debug_settings.dart';
import '../services/stability_monitor.dart';
import '../utils/constants.dart';
import '../utils/i18n.dart';
import '../utils/logger.dart';

class InputPage extends StatefulWidget {
  const InputPage({super.key});

  @override
  State<InputPage> createState() => _InputPageState();
}

class _InputPageState extends State<InputPage> {
  static const List<({String label, String keyName})> _specialKeys = [
    (label: 'Tab', keyName: 'Tab'),
    (label: 'Enter', keyName: 'Enter'),
    (label: 'Esc', keyName: 'Esc'),
    (label: '←', keyName: 'Left'),
    (label: '→', keyName: 'Right'),
    (label: '↑', keyName: 'Up'),
    (label: '↓', keyName: 'Down'),
    (label: 'Home', keyName: 'Home'),
    (label: 'End', keyName: 'End'),
    (label: 'Ctrl+A', keyName: 'Ctrl+A'),
    (label: 'Ctrl+Z', keyName: 'Ctrl+Z'),
    (label: 'Ctrl+C', keyName: 'Ctrl+C'),
    (label: 'Ctrl+V', keyName: 'Ctrl+V'),
  ];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final BleService _bleService = BleService();
  final Protocol _protocol = Protocol();

  late final ThrottledDiffSender _sender;

  ConnectionStateModel _connectionState = ConnectionStateModel.connected;
  bool _inputPaused = false;
  int _segmentCommittedChars = 0;
  Timer? _idleTimer;
  Timer? _waveTimer;
  StreamSubscription<ControlCommand>? _controlSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  int _seq = 1;
  bool _reconnecting = false;
  Object? _lastConnectedDevice;
  bool _waveTick = false;

  int get _totalChars => _segmentCommittedChars + _controller.text.length;

  @override
  void initState() {
    super.initState();
    _sender = ThrottledDiffSender(
      onSend: (delta) {
        Logger.debug('delta sent: ${delta.op} text=${delta.text}');
      },
    );

    _controlSubscription = _bleService.controlCommands.listen(_handleControlCommand);
    _connectionSubscription = _bleService.connectionChanges.listen(_onConnectionChanged);

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    _waveTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _waveTick = !_waveTick;
      });
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _waveTimer?.cancel();
    _controlSubscription?.cancel();
    _connectionSubscription?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onConnectionChanged(bool connected) {
    if (!mounted) {
      return;
    }

    if (connected) {
      setState(() {
        _connectionState = ConnectionStateModel.connected;
      });

      if (_reconnecting) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, zh: '已重连', en: 'Reconnected')), duration: const Duration(milliseconds: 1200)),
        );
      }
      _reconnecting = false;
      return;
    }

    setState(() {
      _connectionState = ConnectionStateModel.disconnected;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, zh: '连接已断开，正在重连...', en: 'Disconnected, reconnecting...'))),
    );

    _startReconnectFlow();
  }

  Future<void> _startReconnectFlow() async {
    if (_reconnecting) {
      return;
    }

    _reconnecting = true;
    StabilityMonitor.instance.recordReconnect();
    for (int attempt = 1; attempt <= 5; attempt++) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = ConnectionStateModel.connecting;
      });

      final delay = Duration(seconds: 1 << (attempt - 1));
      await Future<void>.delayed(delay);

      final device = _lastConnectedDevice;
      if (device == null) {
        continue;
      }

      try {
        await _bleService.connectAsync(device);
        if (!mounted) {
          return;
        }

        _reconnecting = false;
        setState(() {
          _connectionState = ConnectionStateModel.connected;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重连'), duration: Duration(milliseconds: 1200)),
        );
        return;
      } catch (_) {
        StabilityMonitor.instance.recordBleError('reconnect attempt failed');
        // Continue trying until max attempts reached.
      }
    }

    _reconnecting = false;
    if (!mounted) {
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr(context, zh: '重连失败', en: 'Reconnect Failed')),
          content: Text(tr(context, zh: '5 次重连失败，请选择下一步操作。', en: 'Reconnection failed after 5 attempts.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('retry'),
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('goto_connection'),
              child: const Text('Go to Connection Page'),
            ),
          ],
        );
      },
    );

    if (result == 'retry') {
      _startReconnectFlow();
    } else if (result == 'goto_connection' && mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  void _handleControlCommand(ControlCommand command) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (command == ControlCommand.activate) {
        _inputPaused = false;
      } else if (command == ControlCommand.deactivate) {
        _inputPaused = true;
      } else if (command == ControlCommand.clear) {
        _controller.clear();
        _sender.reset();
      }
    });
  }

  void _onTextChanged(String text) {
    if (_inputPaused) {
      return;
    }

    _sender.onTextChanged(text);
    setState(() {});

    _idleTimer?.cancel();
    if (text.length > Constants.autoClearThresholdChars) {
      _idleTimer = Timer(
        const Duration(milliseconds: Constants.autoClearIdleTimeoutMs),
        _autoClearSegment,
      );
    }
  }

  Future<void> _sendSpecialKey(String keyName) async {
    if (_inputPaused) {
      return;
    }

    try {
      await _bleService.sendSpecialKey(keyName, _seq++);
      Logger.debug('special key sent: $keyName');
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, zh: '特殊按键发送失败', en: 'Failed to send special key'))),
      );
    }
  }

  void _autoClearSegment() {
    final text = _controller.text;
    if (text.isEmpty || text.length <= Constants.autoClearThresholdChars) {
      return;
    }

    final totalChars = _segmentCommittedChars + text.length;
    final payload = _protocol.encodeSegmentComplete(_seq++, totalChars);
    Logger.debug('segment complete sent: $payload');

    setState(() {
      _segmentCommittedChars = totalChars;
      _controller.clear();
      _sender.reset();
    });
  }

  Color _statusColor() {
    if (_connectionState == ConnectionStateModel.connected) {
      return Colors.green;
    }
    if (_connectionState == ConnectionStateModel.connecting) {
      return Colors.orange;
    }
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: _statusColor(), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(context, zh: '已连接: ThinkPad', en: 'Connected: ThinkPad'))),
            IconButton(
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (_inputPaused)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr(context, zh: 'PC 已停用输入（DEACTIVATE）', en: 'PC input paused (DEACTIVATE)')),
              ),
            const SizedBox(height: 12),
            if (_reconnecting)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr(context, zh: '连接已断开，正在重连...', en: 'Disconnected, reconnecting...')),
              ),
            Center(
              child: Text(
                tr(context, zh: '在下方输入框中输入文字，文字将实时出现在电脑上', en: 'Type below and text appears on PC in real time.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 18),
            Text(tr(context, zh: '本次已输入: $_totalChars 字', en: 'Characters sent: $_totalChars')),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _specialKeys.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final keyItem = _specialKeys[index];
                  return OutlinedButton(
                    onPressed: () => _sendSpecialKey(keyItem.keyName),
                    child: Text(keyItem.label),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: tr(context, zh: '在此输入...', en: 'Type here...'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
                _InputWave(active: !_inputPaused && !_reconnecting && _connectionState == ConnectionStateModel.connected, tick: _waveTick),
              ],
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: ValueListenableBuilder<bool>(
              valueListenable: DebugSettings.instance.debugModeEnabled,
              builder: (context, enabled, _) {
                if (!enabled) {
                  return const SizedBox.shrink();
                }

                return ValueListenableBuilder<StabilitySnapshot>(
                  valueListenable: StabilityMonitor.instance.snapshot,
                  builder: (context, snapshot, _) {
                    final memoryMb = (snapshot.memoryUsageBytes / (1024 * 1024)).toStringAsFixed(1);
                    return Container(
                      width: 220,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: DefaultTextStyle(
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(context, zh: '调试统计', en: 'Debug stats'), style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(tr(context, zh: '会话时长: ${snapshot.sessionDuration.inMinutes}m ${snapshot.sessionDuration.inSeconds % 60}s', en: 'Session: ${snapshot.sessionDuration.inMinutes}m ${snapshot.sessionDuration.inSeconds % 60}s')),
                            Text(tr(context, zh: '发送字符: ${snapshot.totalCharsSent}', en: 'Chars sent: ${snapshot.totalCharsSent}')),
                            Text(tr(context, zh: 'BLE 包数: ${snapshot.blePacketsSent}', en: 'BLE packets: ${snapshot.blePacketsSent}')),
                            Text(tr(context, zh: 'BLE 字节: ${snapshot.totalBleBytesSent}', en: 'BLE bytes: ${snapshot.totalBleBytesSent}')),
                            Text(tr(context, zh: '内存: ${memoryMb} MB', en: 'Memory: ${memoryMb} MB')),
                            Text(tr(context, zh: '重连次数: ${snapshot.reconnectionCount}', en: 'Reconnects: ${snapshot.reconnectionCount}')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InputWave extends StatelessWidget {
  const _InputWave({required this.active, required this.tick});

  final bool active;
  final bool tick;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      height: 10,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: active
            ? LinearGradient(
                colors: tick
                    ? [color.withOpacity(0.15), color.withOpacity(0.55), color.withOpacity(0.15)]
                    : [color.withOpacity(0.55), color.withOpacity(0.15), color.withOpacity(0.55)],
              )
            : LinearGradient(colors: [color.withOpacity(0.08), color.withOpacity(0.08)]),
      ),
    );
  }
}
