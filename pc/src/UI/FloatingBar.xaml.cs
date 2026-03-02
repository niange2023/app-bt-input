using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using BtInput.Core;
using BtInput.Helpers;

namespace BtInput.UI;

public enum FloatingConnectionStatus
{
    Connected,
    Connecting,
    Disconnected
}

public partial class FloatingBar : Window
{
    private readonly FocusTracker _focusTracker = new();
    private readonly DispatcherTimer _positionTimer;

    public FloatingBar()
    {
        InitializeComponent();

        _positionTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(100)
        };
        _positionTimer.Tick += (_, _) => UpdatePosition();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        var hwnd = new WindowInteropHelper(this).Handle;
        var exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        exStyle |= NativeMethods.WS_EX_NOACTIVATE;
        exStyle |= NativeMethods.WS_EX_TOOLWINDOW;
        exStyle |= NativeMethods.WS_EX_TOPMOST;
        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE, exStyle);
    }

    public void ShowWithFade()
    {
        Show();
        var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150));
        BeginAnimation(OpacityProperty, fadeIn);
        _positionTimer.Start();
    }

    public void HideWithFade()
    {
        var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(150));
        fadeOut.Completed += (_, _) => Hide();
        BeginAnimation(OpacityProperty, fadeOut);
        _positionTimer.Stop();
    }

    public void UpdateStatus(FloatingConnectionStatus status)
    {
        var brush = status switch
        {
            FloatingConnectionStatus.Connected => System.Windows.Media.Brushes.Blue,
            FloatingConnectionStatus.Connecting => System.Windows.Media.Brushes.Orange,
            FloatingConnectionStatus.Disconnected => System.Windows.Media.Brushes.Red,
            _ => System.Windows.Media.Brushes.Blue
        };

        StatusDot.Fill = brush;
    }

    public void UpdateInterimText(string text)
    {
        var nextText = string.IsNullOrWhiteSpace(text) ? "已连接" : text;
        var fadeOut = new DoubleAnimation(1, 0.35, TimeSpan.FromMilliseconds(70));
        fadeOut.Completed += (_, _) =>
        {
            PreviewText.Text = nextText;
            var fadeIn = new DoubleAnimation(0.35, 1, TimeSpan.FromMilliseconds(130));
            PreviewText.BeginAnimation(OpacityProperty, fadeIn);
        };

        PreviewText.BeginAnimation(OpacityProperty, fadeOut);
    }

    public void SetInputActive(bool active)
    {
        if (active)
        {
            TitleText.Text = "BT Input · 输入中";
            StatusDot.Fill = System.Windows.Media.Brushes.Green;
            return;
        }

        TitleText.Text = "BT Input";
    }

    private void UpdatePosition()
    {
        var caret = _focusTracker.GetCaretScreenPosition();
        if (caret is null)
        {
            return;
        }

        Left = caret.Value.X;
        Top = caret.Value.Y + caret.Value.Height + 4;
    }
}
