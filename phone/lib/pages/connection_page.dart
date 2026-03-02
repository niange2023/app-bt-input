import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../utils/i18n.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  bool _isConnecting = false;

  final List<DeviceInfo> _devices = <DeviceInfo>[
    DeviceInfo(name: 'Hai 的 ThinkPad', address: '00:11:22:33:44:55', signalStrength: -52),
    DeviceInfo(name: '办公室台式机', address: '11:22:33:44:55:66', signalStrength: -64),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Future<void> _connectToDevice(DeviceInfo device) async {
    if (_isConnecting) {
      return;
    }
    setState(() {
      _isConnecting = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacementNamed('/input', arguments: device.name);
  }

  Future<void> _refreshDevices() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) {
      return;
    }

    setState(() {
      _devices.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    });
  }

  void _openUsageHelp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UsageHelpPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BT Input'),
        actions: [
          IconButton(
            tooltip: tr(context, zh: '使用说明', en: 'Help'),
            onPressed: _openUsageHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: Listenable.merge([_pulseController, _rotateController]),
              builder: (context, child) {
                final scale = 0.9 + (_pulseController.value * 0.2);
                return Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: _rotateController.value * 6.28318,
                    child: child,
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 2),
                    ),
                  ),
                  Icon(Icons.bluetooth, size: 72, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(_isConnecting ? tr(context, zh: '连接中...', en: 'Connecting...') : tr(context, zh: '正在搜索附近的 BT Input...', en: 'Scanning for nearby BT Input devices...')),
            const SizedBox(height: 8),
            Text(
              tr(context, zh: '确保电脑端 BT Input 已启动', en: 'Make sure BT Input is running on your PC.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshDevices,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _devices.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(device.name),
                        subtitle: Text(tr(context, zh: '信号: ${device.signalStrength} dBm', en: 'Signal: ${device.signalStrength} dBm')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connectToDevice(device),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UsageHelpPage extends StatelessWidget {
  const UsageHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, zh: '使用说明', en: 'Usage Guide'))),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, zh: '1. 先在电脑启动 BT Input。', en: '1. Start BT Input on your PC first.')),
            const SizedBox(height: 8),
            Text(tr(context, zh: '2. 保持手机与电脑蓝牙开启。', en: '2. Keep Bluetooth enabled on both phone and PC.')),
            const SizedBox(height: 8),
            Text(tr(context, zh: '3. 在连接页点击电脑设备完成连接。', en: '3. Tap your PC in the connection page.')),
            const SizedBox(height: 8),
            Text(tr(context, zh: '4. 进入输入页后，输入内容会实时发送到电脑。', en: '4. In Input page, text is sent to PC in real time.')),
          ],
        ),
      ),
    );
  }
}
