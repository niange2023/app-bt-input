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
  int _seq = 1;

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
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
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
            const Center(
              child: Text(
                '在下方输入框中输入文字，文字将实时出现在电脑上',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 18),
            Text('本次已输入: $_totalChars 字'),
            const SizedBox(height: 16),
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
