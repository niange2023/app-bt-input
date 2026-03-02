using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace BtInput.UI;

public enum TrayState
{
    Disconnected,
    Connecting,
    Connected,
    Active
}

public sealed class TrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _toggleItem;
    private readonly Icon _disconnectedIcon;
    private readonly Icon _connectingIcon;
    private readonly Icon _connectedIcon;
    private readonly Icon _activeIcon;

    public event EventHandler? ToggleRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? AboutRequested;
    public event EventHandler? ExitRequested;

    public TrayManager()
    {
        _disconnectedIcon = LoadIcon("tray-gray.ico", SystemIcons.Application);
        _connectingIcon = LoadIcon("tray-yellow.ico", SystemIcons.Warning);
        _connectedIcon = LoadIcon("tray-blue.ico", SystemIcons.Information);
        _activeIcon = LoadIcon("tray-green.ico", SystemIcons.Shield);

        _statusItem = new ToolStripMenuItem("未连接") { Enabled = false };
        _toggleItem = new ToolStripMenuItem("启用 BT Input");
        _toggleItem.Click += (_, _) => ToggleRequested?.Invoke(this, EventArgs.Empty);

        var settingsItem = new ToolStripMenuItem("快捷键设置...");
        settingsItem.Click += (_, _) => SettingsRequested?.Invoke(this, EventArgs.Empty);

        var aboutItem = new ToolStripMenuItem("关于");
        aboutItem.Click += (_, _) => AboutRequested?.Invoke(this, EventArgs.Empty);

        var exitItem = new ToolStripMenuItem("退出");
        exitItem.Click += (_, _) => ExitRequested?.Invoke(this, EventArgs.Empty);

        var menu = new ContextMenuStrip();
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_toggleItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(settingsItem);
        menu.Items.Add(aboutItem);
        menu.Items.Add(exitItem);

        _notifyIcon = new NotifyIcon
        {
            Visible = true,
            Icon = _disconnectedIcon,
            Text = "BT Input - 未连接",
            ContextMenuStrip = menu
        };

        _notifyIcon.DoubleClick += (_, _) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    public void UpdateState(TrayState state, string? deviceName = null, bool activated = false)
    {
        var name = string.IsNullOrWhiteSpace(deviceName) ? "未知设备" : deviceName;
        _statusItem.Text = state switch
        {
            TrayState.Disconnected => "未连接",
            TrayState.Connecting => "连接中...",
            TrayState.Connected => $"已连接: {name}",
            TrayState.Active => $"输入中: {name}",
            _ => "未连接"
        };

        _toggleItem.Checked = activated;
        _notifyIcon.Text = state == TrayState.Disconnected
            ? "BT Input - 未连接"
            : $"BT Input - 已连接: {name}";

        _notifyIcon.Icon = state switch
        {
            TrayState.Disconnected => _disconnectedIcon,
            TrayState.Connecting => _connectingIcon,
            TrayState.Connected => _connectedIcon,
            TrayState.Active => _activeIcon,
            _ => _disconnectedIcon
        };
    }

    private static Icon LoadIcon(string fileName, Icon fallback)
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "assets", "icons", fileName);
            return File.Exists(path) ? new Icon(path) : fallback;
        }
        catch
        {
            return fallback;
        }
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _disconnectedIcon.Dispose();
        _connectingIcon.Dispose();
        _connectedIcon.Dispose();
        _activeIcon.Dispose();
    }
}
