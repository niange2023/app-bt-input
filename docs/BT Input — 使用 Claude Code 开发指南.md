
# BT Input — 使用 Claude Code 开发指南

## 1. 环境准备

### 1.1 安装 Claude Code

```bash
# macOS / Linux / WSL
curl -fsSL https://claude.ai/install.sh | bash

# Windows PowerShell
irm https://claude.ai/install.ps1 | iex

# 验证安装
claude doctor
```

需要 Claude **Max 订阅**（$100/月）才能获得 Opus 模型访问权和充足的 token 配额。BT Input 是双端项目（Flutter + C#），代码量中等，Max5 ($100) 即可。

### 1.2 安装开发工具链

```bash
# Flutter (手机端)
# 从 https://flutter.dev 安装 Flutter SDK 3.x
flutter doctor

# .NET 8 (PC 端)
# 从 https://dotnet.microsoft.com 安装 .NET 8 SDK
dotnet --version

# Git
git init bt-input
cd bt-input
```

### 1.3 项目目录结构（先手动创建骨架）

```
bt-input/
├── CLAUDE.md                    ← 最重要的文件
├── docs/
│   ├── PRD.md                   ← 之前生成的完整文档
│   ├── PROTOCOL.md              ← 协议文档（从 PRD 中拆出）
│   └── ARCHITECTURE.md          ← 架构文档（从 PRD 中拆出）
├── phone/                       ← Flutter 项目（稍后由 Claude 创建）
│   └── ...
├── pc/                          ← C# WPF 项目（稍后由 Claude 创建）
│   └── ...
└── .claude/
    ├── commands/                ← 自定义 slash 命令
    │   ├── phone.md
    │   ├── pc.md
    │   └── test-protocol.md
    └── agents/                  ← 自定义 sub-agent
        ├── flutter-dev.md
        └── csharp-dev.md
```

---

## 2. CLAUDE.md — 最关键的文件

这是 Claude Code **每次对话自动加载**的项目上下文文件。写好它相当于给 Claude 一份完整的项目说明书。

在项目根目录创建 `CLAUDE.md`：

```markdown
# CLAUDE.md — BT Input Project

## Project Overview
BT Input is a cross-platform tool that turns a smartphone into a wireless
input device for Windows PCs via Bluetooth Low Energy (BLE).
Users type on their phone using any system IME (Pinyin, voice, handwriting, etc.)
and text appears in real-time at the PC's cursor position.

## Architecture
- **Phone App**: Flutter 3.x (Dart), cross-platform (Android + iOS)
  - Location: `phone/`
  - BLE plugin: `flutter_blue_plus`
  - Role: BLE Peripheral (GATT Server), hosts input TextField, runs DiffEngine
- **PC App**: C# WPF (.NET 8), Windows only
  - Location: `pc/`
  - BLE: WinRT `Windows.Devices.Bluetooth` APIs
  - Role: BLE Central, receives text deltas, injects via SendInput/Clipboard
  - UI: System tray + floating bar (WS_EX_NOACTIVATE, no focus stealing)

## Key Design Decisions
- PC side is NOT a real IME/TSF. It's a regular app that simulates IME behavior
  (Approach C: normal program + floating bar + SendInput)
- Phone does NOT implement its own input method. It uses a TextField to invoke
  the system IME, then watches text changes via onChanged callback
- Communication: JSON over BLE GATT (MVP). Binary protocol reserved for v2
- Text sync uses prefix+suffix diff algorithm, O(N), covers 95%+ of real input scenarios
- Large text (>10 chars) uses clipboard injection (Ctrl+V) on PC side
- Phone input box auto-clears at 500 chars + 2s idle to support long sessions

## BLE GATT Service
- Service UUID: 0000FFF0-0000-1000-8000-00805F9B34FB
- Text Char (Phone→PC, NOTIFY): 0000FFF1-...
- Control Char (PC→Phone, WRITE): 0000FFF2-...
- Status Char (Phone→PC, NOTIFY): 0000FFF3-...

## Protocol Summary
- Message types: TEXT_DELTA(0x01), TEXT_FULLSYNC(0x02), HEARTBEAT(0x03),
  SEGMENT_COMPLETE(0x06), ACTIVATE(0x81), DEACTIVATE(0x82),
  SYNC_REQUEST(0x83), CLEAR(0x84)
- TEXT_DELTA ops: A(append), I(insert), D(delete), R(replace)
- Reliability: no per-packet ACK; on seq gap → SYNC_REQUEST → FULLSYNC
- Heartbeat: every 5s; timeout at 15s → auto-reconnect
- Throttle: 50ms window, first change fires immediately

## Build & Run Commands
### Phone (Flutter)
```

cd phone
flutter pub get
flutter run             # run on connected device
flutter build apk       # build Android APK
flutter build ios       # build iOS (requires Mac)
flutter test            # run unit tests

```

### PC (C# WPF)
```

cd pc
dotnet restore
dotnet build
dotnet run              # run the app
dotnet test             # run unit tests
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true

```

## Code Style
- Dart: follow `flutter_lints`, use `dart format`
- C#: follow .NET conventions, use `dotnet format`
- All new code must have XML doc comments (C#) or dartdoc comments (Dart)
- Prefer descriptive variable names over abbreviations

## Important Docs
- Full PRD and requirements: `docs/PRD.md`
- BLE protocol specification: `docs/PROTOCOL.md`
- Architecture details: `docs/ARCHITECTURE.md`

## Do NOT
- Do not create a real Windows IME (TSF). We use SendInput approach
- Do not implement speech recognition on the phone. We rely on system IME
- Do not use WiFi or internet. This is BLE-only, fully offline
- Do not auto-merge or push to main without human review
```

> **原则**：CLAUDE.md 要**简洁、精确、可操作**。把详细内容放在 `docs/` 下的引用文件中，而非全部塞进 CLAUDE.md。

---

## 3. 把文档放入 docs/ 目录

把之前生成的完整项目文档拆分后放入 `docs/`：

```bash
# 将之前的完整文档拆分为独立文件
docs/
├── PRD.md                # 产品定义 + 需求 + UI/UX（文档1-3）
├── ARCHITECTURE.md       # 技术方案与架构（文档4）
├── PROTOCOL.md           # BLE通信协议（文档5）
└── LOW_LEVEL_DESIGN.md   # Low Level Design（文档6）
```

Claude Code 会根据 CLAUDE.md 中的指引，在需要时自动去阅读这些文件。

---

## 4. 开发工作流：分阶段、分任务

### 核心原则

Claude Code 的最佳实践：**把大任务分解为聚焦的小任务**，每个任务在一个干净的上下文中完成。

```
❌ 错误方式：
   "帮我把整个 BT Input 项目写完"
   → 上下文爆炸，质量崩塌

✅ 正确方式：
   Phase 1, Task 1: "创建 Flutter 项目骨架和 BLE Service 类"
   Phase 1, Task 2: "实现 DiffEngine 及其单元测试"
   Phase 1, Task 3: "实现手机端输入页 UI + TextWatcher"
   Phase 1, Task 4: "创建 C# WPF 项目骨架和系统托盘"
   Phase 1, Task 5: "实现 PC 端 BLE Central 连接管理"
   Phase 1, Task 6: "实现 PC 端 TextInjectionEngine"
   Phase 1, Task 7: "端到端联调测试"
```

### 4.1 Phase 1 详细任务分解

以下是你可以直接粘贴给 Claude Code 的 prompts：

**Task 1 — Flutter 项目骨架**

```
Read docs/ARCHITECTURE.md for the phone-side architecture.
Create a new Flutter project in the phone/ directory.
Set up the directory structure as specified:
  lib/pages/, lib/services/, lib/core/, lib/models/, lib/utils/
Add flutter_blue_plus dependency to pubspec.yaml.
Create placeholder files for all classes with TODO comments.
Run flutter pub get to verify the setup compiles.
```

**Task 2 — DiffEngine + 单元测试**

```
Read docs/LOW_LEVEL_DESIGN.md section 6.1 for the DiffEngine spec.
Implement DiffEngine in phone/lib/core/diff_engine.dart exactly as specified:
  - Prefix+suffix algorithm, O(N)
  - Handle all scenarios: append, insert, delete, replace, full_sync
  - clipboardHint when text.length > 10
  - FULL_SYNC when change exceeds 60% of original
Write comprehensive unit tests in phone/test/core/diff_engine_test.dart
covering all 7 scenarios from the protocol doc (A through G).
Run flutter test and fix any failures.
```

**Task 3 — 手机端输入页 UI**

```
Read docs/PRD.md section 3.2.3 for the Input Page UI spec.
Implement InputPage in phone/lib/pages/input_page.dart:
  - TextField that auto-focuses and invokes system IME
  - Connection status indicator (green/yellow/red dot)
  - Character count display
  - Auto-clear logic: >500 chars + 2s idle → clear
  - Wire up TextField.onChanged to ThrottledDiffSender (can be stubbed for now)
```

**Task 4 — C# WPF 项目骨架**

```
Read docs/ARCHITECTURE.md section 4.5 for PC-side architecture.
Create a new C# WPF project targeting .NET 8 in the pc/ directory.
Project name: BtInput.
Set up the folder structure: Core/, UI/, Protocol/
Create the system tray implementation using NotifyIcon.
Register global hotkey Ctrl+Shift+B using RegisterHotKey P/Invoke.
The app should start minimized to tray with no main window.
Run dotnet build to verify compilation.
```

**Task 5 — PC 端 BLE Central**

```
Read docs/ARCHITECTURE.md section 4.4 for GATT service UUIDs.
Implement BleManager in pc/src/Core/BleManager.cs:
  - Use Windows.Devices.Bluetooth.GenericAttributeProfile WinRT APIs
  - Scan for BLE devices advertising our service UUID
  - Connect to discovered device
  - Subscribe to Text and Status characteristics (NOTIFY)
  - Write to Control characteristic
  - Auto-reconnect with exponential backoff (1/2/4/8/16s, max 5 attempts)
  - Raise events: OnConnected, OnDisconnected, OnTextReceived, OnStatusReceived
```

**Task 6 — PC 端 TextInjectionEngine**

```
Read docs/LOW_LEVEL_DESIGN.md section 7 for the injection engine spec.
Implement TextInjectionEngine in pc/src/Core/TextInjector.cs:
  - SendInput with KEYEVENTF_UNICODE for short text (≤10 chars)
  - Clipboard injection (save→set→Ctrl+V→restore) for long text (>10 chars)
  - Handle APPEND, DELETE, FULL_SYNC operations
  - For DELETE: send VK_BACK repeated
  - For FULL_SYNC: Ctrl+A then clipboard paste
Implement the FloatingBar WPF window in pc/src/UI/FloatingBar.xaml:
  - WS_EX_NOACTIVATE | WS_EX_TOPMOST | WS_EX_TOOLWINDOW
  - Semi-transparent dark background, rounded corners
  - Show connection status and interim text preview
  - Position: follow caret using GetGUIThreadInfo
```

### 4.2 每个 Task 的工作流

```bash
# 1. 启动新的 Claude Code 会话（干净上下文）
cd bt-input
claude

# 2. 给出聚焦的 prompt（从上面复制）
> Read docs/LOW_LEVEL_DESIGN.md section 6.1 for the DiffEngine spec...

# 3. 让 Claude 实现 + 测试
#    Claude 会：读文件 → 写代码 → 运行测试 → 修复问题

# 4. 验收后提交
> commit these changes with a descriptive message

# 5. 需要新任务时，开启新会话以保持上下文干净
> /clear
# 或退出后重新进入
```

---

## 5. 自定义 Slash 命令

在 `.claude/commands/` 下创建常用命令：

### `.claude/commands/phone.md`

```markdown
---
description: Run Flutter phone app tasks
argument-hint: <task description>
---
You are working on the phone/ Flutter project.
Read CLAUDE.md for project context.

Key files:
- Entry point: phone/lib/main.dart
- BLE: phone/lib/services/ble_service.dart
- Diff: phone/lib/core/diff_engine.dart
- Protocol: phone/lib/core/protocol.dart

Before making changes:
1. Read the relevant section of docs/PROTOCOL.md or docs/LOW_LEVEL_DESIGN.md
2. Run `cd phone && flutter test` after changes
3. Ensure `flutter analyze` reports no issues

Task: $ARGUMENTS
```

### `.claude/commands/pc.md`

```markdown
---
description: Run PC C# WPF tasks
argument-hint: <task description>
---
You are working on the pc/ C# WPF project.
Read CLAUDE.md for project context.

Key files:
- Entry point: pc/src/App.xaml.cs
- BLE: pc/src/Core/BleManager.cs
- Injector: pc/src/Core/TextInjector.cs
- FloatingBar: pc/src/UI/FloatingBar.xaml

Before making changes:
1. Read the relevant section of docs/ARCHITECTURE.md
2. Run `cd pc && dotnet test` after changes
3. Run `cd pc && dotnet build` to verify compilation

Task: $ARGUMENTS
```

**使用方式**：

```
> /phone implement the ThrottledDiffSender with 50ms throttle window
> /pc add auto-reconnect logic to BleManager with exponential backoff
```

---

## 6. 自定义 Sub-Agent

用 Sub-Agent 把探索任务分离到独立上下文中，保持主上下文干净。

### `.claude/agents/flutter-dev.md`

```markdown
---
name: flutter-dev
description: Flutter/Dart development specialist for the phone app.
  Use this agent for implementing features, fixing bugs, and writing
  tests in the phone/ directory.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---
You are a Flutter/Dart specialist working on the phone/ directory.

## Context
Read CLAUDE.md and docs/PROTOCOL.md for project context.

## Rules
- Always run `flutter test` after making changes
- Always run `flutter analyze` to check for issues
- Follow flutter_lints rules
- Write unit tests for all new functions
- Use dartdoc comments on all public APIs
```

### `.claude/agents/csharp-dev.md`

```markdown
---
name: csharp-dev
description: C# WPF development specialist for the PC app.
  Use this agent for implementing features, fixing bugs, and writing
  tests in the pc/ directory.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---
You are a C# / WPF / .NET 8 specialist working on the pc/ directory.

## Context
Read CLAUDE.md and docs/ARCHITECTURE.md for project context.

## Rules
- Always run `dotnet test` after making changes
- Always run `dotnet build` to verify compilation
- Use WinRT APIs for BLE (Windows.Devices.Bluetooth)
- Use P/Invoke for Win32 calls (SendInput, RegisterHotKey, etc.)
- Write XML doc comments on all public APIs
- Never create a real Windows IME/TSF
```

---

## 7. 高级技巧

### 7.1 使用 Plan 模式预先对齐

对于复杂任务，先进入 Plan 模式让 Claude 规划，再执行：

```
> /model opus
> 按 Shift+Tab 切换到 Plan 模式

> Read all docs in docs/ and create a detailed implementation plan for
> Phase 1 MVP. Break it into specific tasks with dependencies.
> For each task, estimate the files to create/modify and key challenges.

# 审核 plan 后
> 按 Shift+Tab 切回 Normal 模式
> Execute task 1 from the plan above
```

### 7.2 并行开发两端

因为 Phone 和 PC 是独立项目，可以**开两个终端窗口并行开发**：

```bash
# Terminal 1 — 手机端
cd bt-input
claude
> /phone create the BLE GATT server implementation

# Terminal 2 — PC 端
cd bt-input
claude
> /pc create the BLE Central scanning and connection logic
```

### 7.3 上下文管理

```bash
# 查看当前上下文使用量
> /context

# 上下文接近 60% 时，做一次 handoff
> Write a summary of everything done in this session,
> pending items, and key decisions to docs/SESSION_LOG.md.
> Then /clear

# 新会话从 log 恢复上下文
> Read docs/SESSION_LOG.md and continue from where we left off
```

### 7.4 模型选择策略

| 任务类型 | 推荐模型 | 理由 |
|---------|---------|------|
| 架构规划、复杂调试 | `opus` | 深度推理能力最强 |
| 日常编码、功能实现 | `sonnet` (默认) | 速度与质量的平衡 |
| Sub-Agent 探索 | `haiku` | 快速廉价，不污染主上下文 |

```bash
# 切换模型
> /model opus    # 复杂架构设计时
> /model sonnet  # 回到日常编码
```

---

## 8. 第一步：现在就开始

```bash
# Step 1: 创建项目目录
mkdir -p bt-input/docs bt-input/.claude/commands bt-input/.claude/agents
cd bt-input
git init

# Step 2: 创建 CLAUDE.md（复制上面第 2 节的内容）
# Step 3: 把项目文档放入 docs/（拆分之前的完整文档）
# Step 4: 创建 slash 命令和 agent（复制上面第 5-6 节的内容）

# Step 5: 开始！
claude

# 你的第一条 prompt：
> Read CLAUDE.md and all files in docs/. Then create the Flutter project
> skeleton in phone/ with the directory structure and placeholder files
> as described in the architecture doc. Add flutter_blue_plus dependency.
> Run flutter pub get to verify setup.
```

---

## 9. 常见问题

| 问题 | 解决方案 |
|------|---------|
| Claude 修改了不该改的文件 | 在 CLAUDE.md 的 "Do NOT" 部分明确禁止 |
| 上下文爆了，Claude 开始犯低级错误 | 用 `/context` 检查，超过 60% 就 handoff + `/clear` |
| 编译错误循环修不好 | 停下来，用 `/model opus` 切到强模型重新分析 |
| BLE 代码 Claude 写错了 | 让 Claude 先读 `docs/PROTOCOL.md` 再修改 |
| 想同时开发两端 | 开两个终端，各自 `claude`，各用各的 slash 命令 |
| Flutter/C# 环境问题 | 让 Claude 跑 `flutter doctor` 或 `dotnet --info` 诊断 |
