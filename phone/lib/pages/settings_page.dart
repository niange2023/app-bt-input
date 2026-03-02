import 'package:flutter/material.dart';

import '../utils/i18n.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _autoClearThreshold = 500;
  double _autoClearTimeout = 2;

  final List<String> _pairedDevices = <String>['办公室台式机', '家里笔记本'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, zh: '设置', en: 'Settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr(context, zh: '连接管理', en: 'Connection'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(tr(context, zh: '当前设备: ThinkPad', en: 'Current device: ThinkPad'))),
                      TextButton(onPressed: () {}, child: Text(tr(context, zh: '断开', en: 'Disconnect'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(tr(context, zh: '已保存设备:', en: 'Paired devices:')),
                  const SizedBox(height: 6),
                  ..._pairedDevices.map((name) => Text('- $name')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(tr(context, zh: '输入设置', en: 'Input'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(tr(context, zh: '自动清空阈值', en: 'Auto-clear threshold'))),
                      Text(tr(context, zh: '${_autoClearThreshold.round()} 字符', en: '${_autoClearThreshold.round()} chars')),
                    ],
                  ),
                  Slider(
                    min: 100,
                    max: 1000,
                    divisions: 18,
                    value: _autoClearThreshold,
                    onChanged: (value) => setState(() => _autoClearThreshold = value),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(tr(context, zh: '清空等待时间', en: 'Clear idle timeout'))),
                      Text(tr(context, zh: '${_autoClearTimeout.toStringAsFixed(1)} 秒', en: '${_autoClearTimeout.toStringAsFixed(1)} s')),
                    ],
                  ),
                  Slider(
                    min: 1,
                    max: 5,
                    divisions: 8,
                    value: _autoClearTimeout,
                    onChanged: (value) => setState(() => _autoClearTimeout = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(tr(context, zh: '关于', en: 'About'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(context, zh: '版本: 1.0.0', en: 'Version: 1.0.0')),
                  const SizedBox(height: 4),
                  const Text('BT Input'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
