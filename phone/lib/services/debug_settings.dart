import 'package:flutter/foundation.dart';

class DebugSettings {
  DebugSettings._();

  static final DebugSettings instance = DebugSettings._();

  final ValueNotifier<bool> debugModeEnabled = ValueNotifier<bool>(false);
}
