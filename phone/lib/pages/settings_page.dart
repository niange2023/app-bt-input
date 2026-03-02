import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('连接管理', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('当前设备: ThinkPad')),
                      TextButton(onPressed: () {}, child: const Text('断开')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('已保存设备:'),
                  const SizedBox(height: 6),
                  ..._pairedDevices.map((name) => Text('- $name')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('输入设置', style: TextStyle(fontWeight: FontWeight.bold)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('自动清空阈值')),
                      Text('${_autoClearThreshold.round()} 字符'),
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
                      const Expanded(child: Text('清空等待时间')),
                      Text('${_autoClearTimeout.toStringAsFixed(1)} 秒'),
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
          const Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('版本: 1.0.0'),
                  SizedBox(height: 4),
                  Text('BT Input'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
