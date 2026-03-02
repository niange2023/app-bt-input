
# BT Input — 开发任务手册 (Development Playbook)

> **使用方法**：按 Round 顺序，将每个 Round 的 Prompt 复制粘贴到 Claude Code 中执行。  
> 每个 Round 完成后 commit，再进入下一个。  
> 如果上下文超过 60%（用 `/context` 检查），执行 `/handoff` + `/clear`，然后用 `/catchup` 恢复。

---

## Phase 1 — MVP（手机 Android + Windows PC，端到端可用）

预计总耗时：2-3 小时

---

### Round 1 — Flutter 项目骨架

**目标**：创建手机端项目结构，能编译通过  
**预计耗时**：~15 分钟

**Prompt**：

```
/phone Create the Flutter project in phone/ directory.
Add flutter_blue_plus to pubspec.yaml.
Create the full directory structure with placeholder files as described in CLAUDE.md:
  lib/main.dart
  lib/app.dart
  lib/pages/connection_page.dart
  lib/pages/input_page.dart
  lib/pages/settings_page.dart
  lib/services/ble_service.dart
  lib/services/connection_manager.dart
  lib/core/diff_engine.dart
  lib/core/throttle_sender.dart
  lib/core/protocol.dart
  lib/models/text_delta.dart
  lib/models/device_info.dart
  lib/models/connection_state.dart
  lib/utils/constants.dart
  lib/utils/logger.dart
Each placeholder file should have the class stub with TODO comments
describing what the class should do.
Run flutter pub get to verify setup compiles.
```

**完成后执行**：

```
commit these changes with message "feat(phone): flutter project skeleton with BLE dependency"
```

**验收标准**：

- [ ] `flutter pub get` 成功
- [ ] `flutter analyze` 无错误
- [ ] 所有 placeholder 文件存在且有 class stub

---

### Round 2 — DiffEngine 核心算法 + 单元测试

**目标**：实现文本增量计算的核心算法，100% 测试覆盖  
**预计耗时**：~15 分钟

**Prompt**：

```
/phone Implement DiffEngine in lib/core/diff_engine.dart.
Read docs/LOW_LEVEL_DESIGN.md for the exact algorithm specification.

Requirements:
- Use the prefix+suffix diff approach, O(N) time complexity
- Handle all scenarios:
  - Empty to non-empty → APPEND
  - Non-empty to empty → DELETE all
  - Identical texts → NO_CHANGE
  - Append at end (most common, ~90% of cases)
  - Insert at arbitrary position
  - Delete at arbitrary position
  - Replace (candidiate word change, auto-correct)
  - Change exceeds 60% of original → FULL_SYNC
- Set clipboardHint = true when text.length > 10

Also implement the TextDelta model class in lib/models/text_delta.dart
with: op (enum), position, deleteCount, text, clipboardHint.

Then write comprehensive unit tests in test/core/diff_engine_test.dart
covering all 7 scenarios from the protocol doc:
  Scenario A: Pinyin char-by-char "你好世界"
  Scenario B: Voice whole sentence (15+ chars at once)
  Scenario C: Candidate replacement "北京" → "南京"
  Scenario D: Auto-complete "苹" → "苹果"
  Scenario E1: Tail delete
  Scenario E2: Middle delete
  Scenario F: Select-all replace (>60% change → FULL_SYNC)
  Scenario G: Middle insert

Run flutter test and fix any failures until all tests pass.
```

**完成后执行**：

```
commit these changes with message "feat(phone): implement DiffEngine with prefix+suffix algorithm and full test coverage"
```

**验收标准**：

- [ ] `flutter test` 全部通过
- [ ] 所有 7 个场景有对应测试用例
- [ ] 边界条件已覆盖（空字符串、单字符、相同文本）

---

### Round 3 — 节流发送器 + 协议编码器

**目标**：实现 50ms 节流控制和 JSON 消息编码  
**预计耗时**：~10 分钟

**Prompt**：

```
/phone Implement two modules:

1. ThrottledDiffSender in lib/core/throttle_sender.dart
   - Accepts a callback for sending deltas (for BLE layer to hook into)
   - On text change: if no timer active, send immediately + start 50ms timer
   - During 50ms window: buffer latest text, don't send
   - When timer fires: if buffered text differs from last sent, send it
   - Tracks previousText state internally via DiffEngine
   - Has a reset() method for when input box is cleared

2. Protocol encoder in lib/core/protocol.dart
   - encode(TextDelta, int seq) → JSON string
   - encodeFullSync(String fullText, int seq) → JSON string
   - encodeHeartbeat(int batteryPercent, String imeName) → JSON string
   - encodeSegmentComplete(int seq, int totalChars) → JSON string
   - JSON format as specified in CLAUDE.md protocol section

Also update lib/utils/constants.dart with:
   - BLE service and characteristic UUIDs
   - Throttle window duration (50ms)
   - Auto-clear threshold (500 chars)
   - Auto-clear idle timeout (2 seconds)
   - Heartbeat interval (5 seconds)
   - All message type codes (0x01, 0x02, etc.)

Write unit tests for ThrottledDiffSender (verify timing behavior)
and Protocol encoder (verify JSON output matches spec).
Run flutter test and fix any failures.
```

**完成后执行**：

```
commit these changes with message "feat(phone): throttled diff sender and protocol JSON encoder"
```

**验收标准**：

- [ ] `flutter test` 全部通过
- [ ] Protocol 编码输出的 JSON 与 CLAUDE.md 中的规格一致
- [ ] ThrottledDiffSender 首次变化立即发送、后续变化在窗口内合并

---

### Round 4 — 手机端 BLE 通信服务

**目标**：实现 BLE GATT Server（Peripheral 角色）  
**预计耗时**：~15 分钟

**Prompt**：

```
/phone Implement BLE communication in lib/services/ble_service.dart
and lib/services/connection_manager.dart.

BleService:
- Initialize flutter_blue_plus
- Set up GATT Server with:
  - Service UUID: 0000FFF0-0000-1000-8000-00805F9B34FB
  - Text Characteristic (NOTIFY): 0000FFF1-...
  - Control Characteristic (WRITE): 0000FFF2-...
  - Status Characteristic (NOTIFY): 0000FFF3-...
- Start advertising when app opens
- sendDelta(TextDelta) → encode to JSON → notify via Text Characteristic
- sendHeartbeat() → notify via Status Characteristic
- Listen on Control Characteristic for PC commands (ACTIVATE, DEACTIVATE, SYNC_REQUEST, CLEAR)
- Handle MTU negotiation (request max MTU on connection)
- If message exceeds MTU, implement the 3-byte header fragmentation protocol from docs/PROTOCOL.md

ConnectionManager:
- Track connection state: disconnected, connecting, connected
- Expose state as a Stream for UI to listen
- Start periodic heartbeat (every 5 seconds) when connected
- Handle disconnect events from flutter_blue_plus
- Provide connect(device) and disconnect() methods

Update lib/models/connection_state.dart with the connection state enum.
Update lib/models/device_info.dart with device name, address, signal strength.

Note: Since flutter_blue_plus's GATT server support varies by platform,
if GATT Server APIs are not available, fall back to using the phone as 
BLE Central and PC as Peripheral. Document the decision in a code comment.
Check flutter_blue_plus docs for the best approach.
```

**完成后执行**：

```
commit these changes with message "feat(phone): BLE GATT service and connection manager"
```

**验收标准**：

- [ ] `flutter analyze` 无错误
- [ ] BleService 完整实现了 3 个 Characteristic
- [ ] ConnectionManager 提供 state stream
- [ ] 心跳定时器在连接时启动、断开时停止

---

### Round 5 — 手机端 UI 三个页面

**目标**：完成手机端所有 UI 页面  
**预计耗时**：~20 分钟

**Prompt**：

```
/phone Implement the three UI pages. Read docs/PRD.md section 3.2 for UI specs.

1. ConnectionPage (lib/pages/connection_page.dart):
   - BLE scanning animation (pulsing Bluetooth icon)
   - List of discovered devices with name and signal strength
   - Tap a device to connect
   - Show "Connecting..." state
   - On successful connection → navigate to InputPage
   - If previously paired device found, auto-connect and skip this page

2. InputPage (lib/pages/input_page.dart) — THE CORE PAGE:
   - Top bar: green/yellow/red dot for connection status + device name + gear icon for settings
   - Center area: guide text "在下方输入框中输入文字，文字将实时出现在电脑上"
   - Character counter: "本次已输入: N 字" (includes chars from cleared segments)
   - Bottom: TextField that auto-focuses 300ms after page load (requestFocus)
   - TextField.onChanged → ThrottledDiffSender.onTextChanged()
   - Auto-clear logic: when text > 500 chars AND user idle for 2 seconds:
     - Send SEGMENT_COMPLETE message
     - Clear the TextField
     - Reset DiffEngine state
     - DO NOT reset the character counter
   - Handle PC control commands:
     - ACTIVATE → (no action needed, already active)
     - DEACTIVATE → show visual indicator that PC paused input
     - CLEAR → clear TextField

3. SettingsPage (lib/pages/settings_page.dart):
   - Current device name with disconnect button
   - List of previously paired devices
   - Auto-clear threshold slider (default 500)
   - Auto-clear idle timeout slider (default 2s)
   - App version info

Set up navigation in app.dart:
- ConnectionPage as initial route
- Named routes for InputPage and SettingsPage
```

**完成后执行**：

```
commit these changes with message "feat(phone): implement all three UI pages with input logic"
```

**验收标准**：

- [ ] `flutter analyze` 无错误
- [ ] App 启动后显示 ConnectionPage
- [ ] InputPage 的 TextField 能自动弹出键盘
- [ ] 字符计数器实时更新
- [ ] 导航流程：Connection → Input → Settings → back

---

### Round 6 — PC 端项目骨架

**目标**：创建 PC 端项目，系统托盘 + 全局热键能用  
**预计耗时**：~15 分钟

**Prompt**：

```
/pc Create a new C# WPF project targeting .NET 8 in the pc/ directory.
Project name: BtInput. Use dotnet new wpf.

Set up the folder structure:
  src/Core/
  src/UI/
  src/Protocol/
  src/Helpers/

Implement the following foundational components:

1. Helpers/NativeMethods.cs — All P/Invoke declarations:
   - SendInput (user32.dll) with INPUT, KEYBDINPUT structs
   - RegisterHotKey / UnregisterHotKey (user32.dll)
   - GetGUIThreadInfo (user32.dll) with GUITHREADINFO struct
   - GetWindowLong / SetWindowLong (user32.dll) for window styles
   - GetForegroundWindow (user32.dll)
   - Constants: WS_EX_NOACTIVATE, WS_EX_TOPMOST, WS_EX_TOOLWINDOW,
     KEYEVENTF_UNICODE, KEYEVENTF_KEYUP, VK_BACK, VK_CONTROL, VK_RETURN

2. Helpers/HotkeyManager.cs:
   - Register global hotkey Ctrl+Shift+B on app startup
   - Fire an event when hotkey is pressed
   - Unregister on app shutdown
   - Use HwndSource.AddHook to handle WM_HOTKEY

3. UI/TrayManager.cs:
   - System tray NotifyIcon (use System.Windows.Forms.NotifyIcon
     or Hardcodet.NotifyIcon.Wpf NuGet package — choose whichever is simpler)
   - 4 icon states: gray (disconnected), yellow (connecting),
     blue (connected), green (active/inputting)
   - Right-click context menu: connection status, enable/disable toggle,
     settings, about, exit
   - Double-click opens settings window
   - Tray icon tooltip shows current status

4. Helpers/Constants.cs:
   - BLE UUIDs (same as phone side)
   - Default hotkey modifiers and key
   - Timeouts and thresholds

5. App.xaml.cs:
   - Override OnStartup: initialize TrayManager + HotkeyManager
   - App starts with NO main window (ShutdownMode = OnExplicitShutdown)
   - Hotkey toggles between activated/deactivated state
   - On exit: cleanup tray icon and unregister hotkey

Run dotnet build and fix any compilation errors.
```

**完成后执行**：

```
commit these changes with message "feat(pc): WPF project skeleton with system tray and global hotkey"
```

**验收标准**：

- [ ] `dotnet build` 成功
- [ ] 运行后仅显示托盘图标，无主窗口
- [ ] Ctrl+Shift+B 能触发（可通过 Debug.WriteLine 验证）
- [ ] 右键托盘图标显示菜单
- [ ] 点击"退出"能正常关闭程序

---

### Round 7 — PC 端 BLE Central 连接管理

**目标**：PC 能扫描、发现、连接手机端 BLE 设备  
**预计耗时**：~20 分钟

**Prompt**：

```
/pc Implement BLE Central in src/Core/BleManager.cs.
Read docs/PROTOCOL.md for GATT service and characteristic UUIDs.

Use WinRT APIs: Windows.Devices.Bluetooth and
Windows.Devices.Bluetooth.GenericAttributeProfile.

Requirements:
1. StartScanAsync():
   - Use BluetoothLEAdvertisementWatcher
   - Filter by our service UUID (0000FFF0-...)
   - Report discovered devices with name and address
   - Stop scanning after connection or timeout (30s)

2. ConnectAsync(ulong bluetoothAddress):
   - BluetoothLEDevice.FromBluetoothAddressAsync
   - Get GATT services for our UUID
   - Get all 3 characteristics
   - Subscribe to Text and Status characteristics (NOTIFY)
   - Request high connection priority
   - Negotiate MTU

3. Event handlers:
   - OnTextDataReceived(byte[] data) — raw bytes from Text Characteristic
   - OnStatusDataReceived(byte[] data) — raw bytes from Status Characteristic
   - OnConnectionStatusChanged(connected/disconnected)

4. SendControlAsync(byte[] data):
   - Write to Control Characteristic (with response)

5. Auto-reconnect:
   - On unexpected disconnect, start reconnection loop
   - Exponential backoff: 1s, 2s, 4s, 8s, 16s
   - Max 5 attempts, then stop and notify user
   - On successful reconnect, send SYNC_REQUEST (0x83)

6. Expose public events/properties:
   - event Action<byte[]> TextDataReceived
   - event Action<byte[]> StatusDataReceived
   - event Action<bool> ConnectionChanged
   - bool IsConnected { get; }
   - string ConnectedDeviceName { get; }

7. Cleanup:
   - DisposeAsync() to release all BLE resources
   - Unsubscribe from characteristics before disconnect

Run dotnet build and fix any compilation errors.
```

**完成后执行**：

```
commit these changes with message "feat(pc): BLE Central with scan, connect, subscribe, and auto-reconnect"
```

**验收标准**：

- [ ] `dotnet build` 成功
- [ ] BleManager 暴露了所有必需的事件和方法
- [ ] 自动重连逻辑包含指数退避
- [ ] 重连成功后发送 SYNC_REQUEST

---

### Round 8 — PC 端协议解码 + 文本注入引擎

**目标**：收到 BLE 数据后能正确解码并注入到 PC 窗口  
**预计耗时**：~20 分钟

**Prompt**：

```
/pc Implement the protocol decoder and text injection engine.

1. Protocol/Messages.cs — Data models:
   - enum MessageType { TextDelta=0x01, TextFullSync=0x02, Heartbeat=0x03, ... }
   - enum DeltaOp { Append, Insert, Delete, Replace }
   - class TextDeltaMessage { MessageType, int Seq, DeltaOp Op, int Position,
     int DeleteCount, string Text, bool ClipboardHint }
   - class HeartbeatMessage { int Battery, string ImeName }
   - class SegmentCompleteMessage { int Seq, int TotalChars }

2. Core/ProtocolDecoder.cs:
   - Decode(byte[] rawBytes) → returns the appropriate message object
   - Handle JSON deserialization with System.Text.Json
   - Handle MTU fragmentation reassembly:
     - Parse 3-byte header (msg_id, seq/flags, total_packets)
     - Buffer partial packets by msg_id
     - When last packet received (flags bit 0 = 1), reassemble and decode
   - Validate sequence numbers, detect gaps

3. Core/TextInjector.cs:
   - InjectText(string text):
     - If text.Length <= 10: use SendInput with KEYEVENTF_UNICODE
       - For each char in text: send key-down + key-up events
     - If text.Length > 10: use clipboard injection
       - Save current clipboard content
       - Set clipboard to text
       - Simulate Ctrl+V (SendInput)
       - After 50ms delay, restore original clipboard
   
   - InjectBackspace(int count):
     - Send VK_BACK key events, repeated count times
   
   - InjectFullSync(string fullText):
     - Send Ctrl+A (select all)
     - Then clipboard inject the full text
   
   - HandleDelta(TextDeltaMessage msg):
     - Switch on msg.Op:
       - Append → InjectText(msg.Text)
       - Delete → InjectBackspace(msg.DeleteCount)
       - Insert/Replace → InjectFullSync (simplified: treat as full resync)
       - Also handle via clipboard hint flag

4. Wire everything together in App.xaml.cs:
   - BleManager.TextDataReceived → ProtocolDecoder.Decode → TextInjector.HandleDelta
   - BleManager.ConnectionChanged → update TrayManager icon state
   - HotkeyManager.HotkeyPressed → toggle activated state
     - Activated: start processing incoming text
     - Deactivated: ignore incoming text, send DEACTIVATE to phone
   - On connection, send ACTIVATE (0x81) to phone

Write unit tests for ProtocolDecoder (verify JSON parsing for all message types)
and TextInjector (verify correct SendInput calls — mock the P/Invoke layer).
Run dotnet build and dotnet test.
```

**完成后执行**：

```
commit these changes with message "feat(pc): protocol decoder, text injector, and end-to-end message wiring"
```

**验收标准**：

- [ ] `dotnet build` 成功
- [ ] `dotnet test` 通过
- [ ] ProtocolDecoder 能解析所有 6 种消息类型
- [ ] TextInjector 对短文本用 SendInput，长文本用剪贴板
- [ ] App.xaml.cs 完成了 BLE → Decode → Inject 的完整链路

---

### Round 9 — PC 端浮动状态条

**目标**：实现仿输入法的浮动窗口  
**预计耗时**：~15 分钟

**Prompt**：

```
/pc Implement the FloatingBar in src/UI/FloatingBar.xaml and FloatingBar.xaml.cs.
Read docs/PRD.md section 3.3.2 for visual specs.

XAML Layout:
- Window: WindowStyle=None, AllowsTransparency=True, Background=Transparent,
  Topmost=True, ShowInTaskbar=False, ResizeMode=NoResize
- Content: Border with Background="#CC333333", CornerRadius=8, Padding="12,6"
  - StackPanel Orientation=Horizontal:
    - Ellipse 10x10 (status dot: green/blue/red, bound to state)
    - TextBlock "BT Input" in white, FontSize=13, Margin="8,0,0,0"
    - TextBlock for interim text preview, Foreground="#80FFFFFF", FontSize=13,
      Margin="8,0,0,0", MaxWidth=300, TextTrimming=CharacterEllipsis

Code-behind:
1. OnSourceInitialized:
   - Get HWND via WindowInteropHelper
   - SetWindowLong to add WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW
   - This ensures the window NEVER steals focus

2. Position tracking:
   - DispatcherTimer at 100ms interval
   - Call GetGUIThreadInfo(0, ref info) to get current caret position
   - Convert screen coordinates
   - Set this.Left = caret.Left, this.Top = caret.Bottom + 4
   - If caret position is (0,0), don't move (no active text input)

3. Public methods:
   - Show() with 150ms fade-in animation (Opacity 0→1)
   - Hide() with 150ms fade-out animation (Opacity 1→0)
   - UpdateStatus(ConnectionStatus status) — changes dot color
   - UpdateInterimText(string text) — updates preview text
   - SetInputActive(bool active) — toggles between idle/active visual state

4. FocusTracker integration in src/Core/FocusTracker.cs:
   - Wraps GetGUIThreadInfo calls
   - Provides GetCaretScreenPosition() → (x, y, width, height)?
   - Returns null if no active text input detected
   - Used by FloatingBar for positioning

Wire into App.xaml.cs:
- Hotkey toggle → FloatingBar.Show() / FloatingBar.Hide()
- BLE text received → FloatingBar.UpdateInterimText(lastText)
- Connection state change → FloatingBar.UpdateStatus()

Run dotnet build.
```

**完成后执行**：

```
commit these changes with message "feat(pc): floating IME-style status bar with caret tracking"
```

**验收标准**：

- [ ] `dotnet build` 成功
- [ ] 浮动条使用 `WS_EX_NOACTIVATE`（不抢焦点）
- [ ] 浮动条使用 `WS_EX_TOOLWINDOW`（不显示在 Alt+Tab）
- [ ] Ctrl+Shift+B 切换浮动条显示/隐藏
- [ ] 浮动条跟随光标位置

---

### Round 10 — 端到端联调

**目标**：在真实设备上验证完整流程  
**预计耗时**：~30 分钟（包含调试时间）

**Prompt**：

```
/e2e all

Before testing on real devices, do a final code review:

1. Read through the complete data flow:
   Phone TextField.onChanged
   → ThrottledDiffSender
   → DiffEngine.computeDelta
   → Protocol.encode (JSON)
   → BleService.sendDelta (GATT Notify)
   → [BLE transmission]
   → PC BleManager.TextDataReceived
   → ProtocolDecoder.Decode
   → TextInjector.HandleDelta
   → SendInput / Clipboard inject
   → Text appears at cursor

2. Verify all UUIDs match between phone and PC code.

3. Verify JSON field names match between encoder (Dart) and decoder (C#):
   "t", "s", "o", "p", "n", "d", "c"

4. Check that MTU fragmentation header format is identical on both sides.

5. Add any missing error handling:
   - BLE disconnection during send
   - JSON parse failures (malformed data)
   - SendInput failures (no foreground window)
   - Clipboard access failures

6. Add logging throughout the pipeline for debugging:
   - Phone: print/debugPrint for BLE events and sent messages
   - PC: Debug.WriteLine or a simple file logger for received messages and injection events

Fix any issues found. Run all tests on both sides.
```

**完成后执行**：

```
commit these changes with message "fix: end-to-end code review, error handling, and logging"
```

然后保存进度：

```
/handoff
```

---

## Phase 2 — 体验优化（在 MVP 验证通过后执行）

预计总耗时：2-3 小时

---

### Round 11 — 自动重连体验优化

**Prompt**：

```
/phone Improve the reconnection experience:
1. When BLE disconnects, show a non-intrusive snackbar "连接已断开，正在重连..."
2. Keep the InputPage visible (don't navigate back to ConnectionPage)
3. When reconnected, show brief "已重连" toast and resume normal operation
4. If reconnection fails after 5 attempts, show a dialog with
   "Retry" and "Go to Connection Page" options

/pc Improve reconnection on PC side:
1. On disconnect, FloatingBar shows "🔴 连接已断开 · 重连中..."
2. Buffer any text deltas received during reconnection (don't discard)
3. On reconnect, send SYNC_REQUEST and wait for FULLSYNC before resuming injection
4. Tray icon changes to yellow during reconnection
```

**完成后执行**：

```
commit these changes with message "feat: improved reconnection UX on both sides"
```

---

### Round 12 — 首次使用引导

**Prompt**：

```
/pc Create the first-run experience:
1. Implement FirstRunWindow.xaml:
   - Step-by-step guide: install phone app → enable Bluetooth → select this PC
   - Show PC device name prominently
   - Show a "waiting for connection..." animation
   - Auto-close when phone connects
2. On first launch (check a flag in settings), show FirstRunWindow instead of just tray icon
3. Save "first run completed" flag after successful first connection

/phone Improve ConnectionPage for first-time users:
1. Add brief instruction text: "确保电脑端 BT Input 已启动"
2. Show a pull-to-refresh gesture on the device list
3. Add a "help" button linking to usage instructions
```

**完成后执行**：

```
commit these changes with message "feat: first-run onboarding experience"
```

---

### Round 13 — 快捷键自定义 + 开机自启动

**Prompt**：

```
/pc Implement settings persistence and customization:
1. Create a simple JSON settings file at %APPDATA%/BtInput/settings.json
2. SettingsWindow.xaml with:
   - Hotkey customization: text field showing current hotkey, 
     press a key combination to change
   - "开机自启动" checkbox (implement via Registry Run key)
   - "记住上次连接的设备" checkbox
   - Save/Cancel buttons
3. Load settings on startup, apply hotkey and auto-start preferences
4. If "remember device" is on, auto-connect to last device on startup
```

**完成后执行**：

```
commit these changes with message "feat(pc): settings persistence, custom hotkey, and auto-start"
```

---

### Round 14 — 特殊按键支持

**Prompt**：

```
Implement special key support on both sides.

/phone Add a special keys toolbar above the TextField:
- A horizontal scrollable row of buttons:
  [Tab] [Enter] [Esc] [←] [→] [↑] [↓] [Home] [End] [Ctrl+A] [Ctrl+Z] [Ctrl+C] [Ctrl+V]
- Each button sends a special key message (not text)
- Add a new message type SPECIAL_KEY (0x07):
  {"t":7, "s":N, "k":"Tab"}  // or "Enter", "Left", "Right", etc.

/pc Handle SPECIAL_KEY messages in ProtocolDecoder and TextInjector:
- Map key names to virtual key codes
- Send via SendInput with the appropriate VK_ code
- For Ctrl combinations: send Ctrl down → key → Ctrl up
```

**完成后执行**：

```
commit these changes with message "feat: special key support (Tab, Enter, arrows, Ctrl combos)"
```

---

### Round 15 — 深色模式 + UI 打磨

**Prompt**：

```
/phone Polish the UI:
1. Add dark mode support: detect system brightness, apply dark/light theme
2. InputPage: add a subtle wave animation at the bottom when actively receiving input
3. ConnectionPage: improve the scanning animation
4. Add app icon (use a simple BT + keyboard icon concept)
5. Ensure all text is properly localized (Chinese + English)

/pc Polish the PC UI:
1. FloatingBar: add smooth animation when text preview updates
2. Create proper .ico file with all 4 status states (gray/yellow/blue/green)
3. Tray tooltip: show "BT Input - 已连接: [设备名]" or "BT Input - 未连接"
```

**完成后执行**：

```
commit these changes with message "feat: dark mode, UI polish, and app icons"
```

---

## Phase 3 — iOS 适配 + 产品化（在 Phase 2 完成后执行）

预计总耗时：3-4 小时

---

### Round 16 — iOS 适配

**Prompt**：

```
/phone Adapt the Flutter app for iOS:
1. Review all flutter_blue_plus API calls for iOS compatibility
2. iOS BLE specifics:
   - iOS max MTU is typically 185 bytes — ensure fragmentation works
   - iOS background BLE is restricted — add appropriate Background Modes
     in ios/Runner/Info.plist (bluetooth-central, bluetooth-peripheral)
   - Add NSBluetoothAlwaysUsageDescription to Info.plist
3. Test that flutter build ios succeeds (if on macOS)
4. Handle iOS-specific permission flows (Bluetooth permission dialog)
5. Document any iOS limitations in a comment block at the top of ble_service.dart
```

---

### Round 17 — 长时间稳定性测试

**Prompt**：

```
/phone Add stability monitoring:
1. Track and log memory usage every 60 seconds
2. Track total BLE bytes sent
3. Log any BLE errors or reconnection events
4. Add a debug mode (enabled in SettingsPage) that shows a real-time stats overlay:
   - Session duration
   - Total chars sent
   - BLE packets sent
   - Current memory usage
   - Reconnection count

/pc Add stability monitoring:
1. Log all received messages with timestamps
2. Track sequence number gaps (count of SYNC_REQUEST sent)
3. Monitor memory usage
4. Add debug logging to a file at %APPDATA%/BtInput/debug.log
   (only when debug mode is on)
```

---

### Round 18 — 打包发布

**Prompt**：

```
/pc Prepare for distribution:
1. dotnet publish single-file self-contained exe
2. Add assembly info: product name, version, company, icon
3. Create a simple NSIS or Inno Setup installer script (optional)
4. Write a README.md with:
   - What is BT Input
   - System requirements
   - Installation instructions
   - Usage guide with screenshots
   - Troubleshooting FAQ

/phone Prepare for distribution:
1. flutter build apk --release
2. Update android/app/build.gradle: applicationId, versionName, versionCode
3. Add a proper app icon using flutter_launcher_icons
4. Write a Play Store description draft
```

---

## 附录：常用操作速查

| 场景 | 命令 |
|------|------|
| 开始新会话 | `claude` |
| 恢复上次进度 | `/catchup` |
| 保存当前进度 | `/handoff` |
| 检查上下文使用量 | `/context` |
| 清空上下文重新开始 | `/clear` |
| 切到强模型（复杂问题） | `/model opus` |
| 切回日常模型 | `/model sonnet` |
| 手机端任务 | `/phone <任务描述>` |
| PC 端任务 | `/pc <任务描述>` |
| 协议验证 | `/test-protocol all` |
| 端到端测试 | `/e2e all` |
| 提交代码 | `commit these changes with message "..."` |
| 查看 git 状态 | `git status` |
| 查看最近提交 | `git log --oneline -5` |
