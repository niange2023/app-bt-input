import 'package:flutter/material.dart';

import 'dart:async';

import '../core/protocol.dart';
import '../core/throttle_sender.dart';
import '../models/connection_state.dart';
import '../services/ble_service.dart';
import '../utils/constants.dart';
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
  StreamSubscription<ControlCommand>? _controlSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  int _seq = 1;
  bool _reconnecting = false;
  Object? _lastConnectedDevice;

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
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
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
          const SnackBar(content: Text('已重连'), duration: Duration(milliseconds: 1200)),
        );
      }
      _reconnecting = false;
      return;
    }

    setState(() {
      _connectionState = ConnectionStateModel.disconnected;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('连接已断开，正在重连...')),
    );

    _startReconnectFlow();
  }

  Future<void> _startReconnectFlow() async {
    if (_reconnecting) {
      return;
    }

    _reconnecting = true;
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
          title: const Text('重连失败'),
          content: const Text('5 次重连失败，请选择下一步操作。'),
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
        const SnackBar(content: Text('特殊按键发送失败')),
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
            const Expanded(child: Text('已连接: ThinkPad')),
            IconButton(
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
              icon: const Icon(Icons.settings),
            ),
          ],
        ),
      ),
      body: Padding(
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
                child: const Text('PC 已停用输入（DEACTIVATE）'),
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
                child: const Text('连接已断开，正在重连...'),
              ),
            const Center(
              child: Text(
                '在下方输入框中输入文字，文字将实时出现在电脑上',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 18),
            Text('本次已输入: $_totalChars 字'),
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
              decoration: const InputDecoration(
                hintText: '在此输入...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
