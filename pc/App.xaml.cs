using System.Windows;
using System.Text;
using BtInput.Core;
using BtInput.Helpers;
using BtInput.Protocol;
using BtInput.UI;

namespace BtInput;

public partial class App : System.Windows.Application
{
    private TrayManager? _trayManager;
    private HotkeyManager? _hotkeyManager;
    private StartupManager? _startupManager;
    private BleManager? _bleManager;
    private ProtocolDecoder? _protocolDecoder;
    private TextInjector? _textInjector;
    private FloatingBar? _floatingBar;
    private readonly Queue<TextDeltaMessage> _bufferedDeltas = new();
    private AppSettingsStore? _settingsStore;
    private DebugFileLogger? _debugLogger;
    private PcStabilityMonitor? _pcStabilityMonitor;
    private AppSettings _settings = AppSettings.Default;
    private FirstRunWindow? _firstRunWindow;
    private bool _isActivated;
    private bool _isReconnecting;
    private bool _awaitingFullSync;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _settingsStore = new AppSettingsStore();
        _settings = _settingsStore.Load();
        _debugLogger = new DebugFileLogger(_settings.DebugModeEnabled);
        _pcStabilityMonitor = new PcStabilityMonitor(_debugLogger);
        _pcStabilityMonitor.Start();

        _trayManager = new TrayManager();
        _trayManager.ExitRequested += (_, _) => Shutdown();
        _trayManager.ToggleRequested += (_, _) => ToggleActivation();
        _trayManager.SettingsRequested += (_, _) => OpenSettings();
        _trayManager.UpdateState(TrayState.Disconnected);

        _hotkeyManager = new HotkeyManager();
        _hotkeyManager.HotkeyPressed += (_, _) => ToggleActivation();
        _hotkeyManager.Register(_settings.HotkeyModifiers, _settings.HotkeyVirtualKey);

        _startupManager = new StartupManager();
        _startupManager.Apply(_settings.AutoStartEnabled);

        _protocolDecoder = new ProtocolDecoder();
        _textInjector = new TextInjector();
        _bleManager = new BleManager();
        _bleManager.TextDataReceived += OnTextDataReceived;
        _bleManager.ConnectionChanged += OnConnectionChanged;

        _floatingBar = new FloatingBar();

        if (_settings.RememberLastDevice && _settings.LastDeviceAddress is > 0)
        {
            _ = TryAutoConnectRememberedDeviceAsync(_settings.LastDeviceAddress.Value);
        }

        if (!_settings.FirstRunCompleted)
        {
            _firstRunWindow = new FirstRunWindow();
            _firstRunWindow.SetPcDeviceName(Environment.MachineName);
            _firstRunWindow.Show();
        }
    }

    private async Task TryAutoConnectRememberedDeviceAsync(ulong deviceAddress)
    {
        if (_bleManager is null)
        {
            return;
        }

        try
        {
            await _bleManager.ConnectAsync(deviceAddress);
        }
        catch
        {
        }
    }

    private async void OnConnectionChanged(bool connected)
    {
        _debugLogger?.Log($"Connection changed: connected={connected}");

        if (connected && !_settings.FirstRunCompleted && _settingsStore is not null)
        {
            _settings.FirstRunCompleted = true;
            _settingsStore.Save(_settings);
            await Dispatcher.InvokeAsync(() =>
            {
                _firstRunWindow?.Close();
                _firstRunWindow = null;
            });
        }

        if (connected && _settingsStore is not null && _bleManager is not null && _settings.RememberLastDevice)
        {
            _settings.LastDeviceAddress = _bleManager.ConnectedDeviceAddress;
            _settings.LastDeviceName = _bleManager.ConnectedDeviceName;
            _settingsStore.Save(_settings);
        }

        if (connected)
        {
            _awaitingFullSync = true;
            _trayManager?.UpdateState(TrayState.Connecting, deviceName: _bleManager?.ConnectedDeviceName, activated: _isActivated);
            _floatingBar?.UpdateStatus(FloatingConnectionStatus.Connecting);
            _floatingBar?.UpdateInterimText("同步中...");
            if (_bleManager is not null)
            {
                await _bleManager.SendControlAsync(Encoding.UTF8.GetBytes("{\"t\":131}"));
            }
        }
        else
        {
            _isReconnecting = true;
            _awaitingFullSync = true;
            _trayManager?.UpdateState(TrayState.Connecting, deviceName: _bleManager?.ConnectedDeviceName, activated: _isActivated);
            _floatingBar?.UpdateStatus(FloatingConnectionStatus.Disconnected);
            _floatingBar?.UpdateInterimText("🔴 连接已断开 · 重连中...");
        }
    }

    private async void OnTextDataReceived(byte[] bytes)
    {
        if (!_isActivated || _protocolDecoder is null || _textInjector is null || _bleManager is null)
        {
            return;
        }

        var message = _protocolDecoder.Decode(bytes);
        _pcStabilityMonitor?.RecordReceivedMessage(bytes.Length, message?.GetType().Name ?? "Unknown");
        if (message is TextFullSyncMessage fullSync)
        {
            if (_awaitingFullSync)
            {
                _textInjector.InjectFullSync(fullSync.Text);
                _awaitingFullSync = false;
                _isReconnecting = false;

                while (_bufferedDeltas.Count > 0)
                {
                    var buffered = _bufferedDeltas.Dequeue();
                    _textInjector.HandleDelta(buffered);
                }

                _trayManager?.UpdateState(_isActivated ? TrayState.Active : TrayState.Connected, deviceName: _bleManager.ConnectedDeviceName, activated: _isActivated);
                _floatingBar?.UpdateStatus(FloatingConnectionStatus.Connected);
                _floatingBar?.UpdateInterimText("已重连");
            }
            return;
        }

        if (message is TextDeltaMessage textDeltaMessage)
        {
            if (_isReconnecting || _awaitingFullSync)
            {
                _bufferedDeltas.Enqueue(textDeltaMessage);
                _floatingBar?.UpdateInterimText("🔴 连接已断开 · 重连中...");
                return;
            }

            _textInjector.HandleDelta(textDeltaMessage);
            _trayManager?.UpdateState(TrayState.Active, deviceName: _bleManager.ConnectedDeviceName, activated: true);
            _floatingBar?.SetInputActive(true);
            _floatingBar?.UpdateInterimText(textDeltaMessage.Text);
        }

        if (message is SpecialKeyMessage specialKeyMessage)
        {
            if (_isReconnecting || _awaitingFullSync)
            {
                _floatingBar?.UpdateInterimText("🔴 连接已断开 · 重连中...");
                return;
            }

            _textInjector.HandleSpecialKey(specialKeyMessage);
            _trayManager?.UpdateState(TrayState.Active, deviceName: _bleManager.ConnectedDeviceName, activated: true);
            _floatingBar?.SetInputActive(true);
            _floatingBar?.UpdateInterimText($"按键: {specialKeyMessage.Key}");
        }

        if (_protocolDecoder.SequenceGapDetected)
        {
            _awaitingFullSync = true;
            _pcStabilityMonitor?.RecordSyncRequestSent();
            await _bleManager.SendControlAsync(Encoding.UTF8.GetBytes("{\"t\":131}"));
        }
    }

    private async void ToggleActivation()
    {
        _isActivated = !_isActivated;
        var trayState = _isActivated ? TrayState.Active : TrayState.Connected;
        _trayManager?.UpdateState(trayState, deviceName: "示例设备", activated: _isActivated);

        if (_isActivated)
        {
            _floatingBar?.ShowWithFade();
        }
        else
        {
            _floatingBar?.HideWithFade();
        }

        if (_bleManager is not null)
        {
            var controlPayload = _isActivated ? "{\"t\":129}" : "{\"t\":130}";
            await _bleManager.SendControlAsync(Encoding.UTF8.GetBytes(controlPayload));
        }
    }

    private void OpenSettings()
    {
        if (_settingsStore is null || _hotkeyManager is null || _startupManager is null)
        {
            return;
        }

        var window = new SettingsWindow(_settings)
        {
            Owner = Current?.Windows.OfType<System.Windows.Window>().FirstOrDefault(window => window.IsActive)
        };

        var result = window.ShowDialog();
        if (result != true || window.ResultSettings is null)
        {
            return;
        }

        var updatedSettings = window.ResultSettings;
        updatedSettings.FirstRunCompleted = _settings.FirstRunCompleted;
        updatedSettings.LastDeviceAddress = updatedSettings.RememberLastDevice ? _settings.LastDeviceAddress : null;
        updatedSettings.LastDeviceName = updatedSettings.RememberLastDevice ? _settings.LastDeviceName : null;

        _settings = updatedSettings;
        _settingsStore.Save(_settings);
        if (_debugLogger is not null)
        {
            _debugLogger.IsEnabled = _settings.DebugModeEnabled;
            _debugLogger.Log("Debug mode setting changed.");
        }

        _hotkeyManager.Unregister();
        _hotkeyManager.Register(_settings.HotkeyModifiers, _settings.HotkeyVirtualKey);
        _startupManager.Apply(_settings.AutoStartEnabled);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Dispose();
        _trayManager?.Dispose();
        _pcStabilityMonitor?.Dispose();
        if (_bleManager is not null)
        {
            _ = _bleManager.DisposeAsync();
        }
        _floatingBar?.Close();
        base.OnExit(e);
    }
}

