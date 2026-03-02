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
    private BleManager? _bleManager;
    private ProtocolDecoder? _protocolDecoder;
    private TextInjector? _textInjector;
    private FloatingBar? _floatingBar;
    private readonly Queue<TextDeltaMessage> _bufferedDeltas = new();
    private bool _isActivated;
    private bool _isReconnecting;
    private bool _awaitingFullSync;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _trayManager = new TrayManager();
        _trayManager.ExitRequested += (_, _) => Shutdown();
        _trayManager.ToggleRequested += (_, _) => ToggleActivation();
        _trayManager.UpdateState(TrayState.Disconnected);

        _hotkeyManager = new HotkeyManager();
        _hotkeyManager.HotkeyPressed += (_, _) => ToggleActivation();
        _hotkeyManager.Register(Constants.DefaultHotkeyModifiers, Constants.DefaultHotkeyVirtualKey);

        _protocolDecoder = new ProtocolDecoder();
        _textInjector = new TextInjector();
        _bleManager = new BleManager();
        _bleManager.TextDataReceived += OnTextDataReceived;
        _bleManager.ConnectionChanged += OnConnectionChanged;

        _floatingBar = new FloatingBar();
    }

    private async void OnConnectionChanged(bool connected)
    {
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

        if (_protocolDecoder.SequenceGapDetected)
        {
            _awaitingFullSync = true;
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

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeyManager?.Dispose();
        _trayManager?.Dispose();
        if (_bleManager is not null)
        {
            _ = _bleManager.DisposeAsync();
        }
        _floatingBar?.Close();
        base.OnExit(e);
    }
}

