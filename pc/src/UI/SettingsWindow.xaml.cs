using System.Windows;
using System.Windows.Input;
using BtInput.Helpers;

namespace BtInput.UI;

public partial class SettingsWindow : Window
{
    private readonly AppSettings _baseSettings;
    private uint _hotkeyModifiers;
    private uint _hotkeyVirtualKey;

    public SettingsWindow(AppSettings settings)
    {
        InitializeComponent();

        _baseSettings = settings;

        _hotkeyModifiers = settings.HotkeyModifiers;
        _hotkeyVirtualKey = settings.HotkeyVirtualKey;

        HotkeyTextBox.Text = FormatHotkey(_hotkeyModifiers, _hotkeyVirtualKey);
        AutoStartCheckBox.IsChecked = settings.AutoStartEnabled;
        RememberDeviceCheckBox.IsChecked = settings.RememberLastDevice;
    }

    public AppSettings? ResultSettings { get; private set; }

    private void HotkeyTextBox_OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift)
        {
            e.Handled = true;
            return;
        }

        var modifiers = ToNativeModifiers(Keyboard.Modifiers);
        if (modifiers == 0)
        {
            e.Handled = true;
            return;
        }

        var virtualKey = (uint)KeyInterop.VirtualKeyFromKey(key);
        if (virtualKey == 0)
        {
            e.Handled = true;
            return;
        }

        _hotkeyModifiers = modifiers;
        _hotkeyVirtualKey = virtualKey;
        HotkeyTextBox.Text = FormatHotkey(_hotkeyModifiers, _hotkeyVirtualKey);
        e.Handled = true;
    }

    private void SaveButton_OnClick(object sender, RoutedEventArgs e)
    {
        ResultSettings = new AppSettings
        {
            FirstRunCompleted = _baseSettings.FirstRunCompleted,
            HotkeyModifiers = _hotkeyModifiers,
            HotkeyVirtualKey = _hotkeyVirtualKey,
            AutoStartEnabled = AutoStartCheckBox.IsChecked == true,
            RememberLastDevice = RememberDeviceCheckBox.IsChecked == true,
            LastDeviceAddress = _baseSettings.LastDeviceAddress,
            LastDeviceName = _baseSettings.LastDeviceName
        };

        DialogResult = true;
        Close();
    }

    private void CancelButton_OnClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private static uint ToNativeModifiers(ModifierKeys modifiers)
    {
        uint result = 0;
        if ((modifiers & ModifierKeys.Control) == ModifierKeys.Control)
        {
            result |= NativeMethods.MOD_CONTROL;
        }

        if ((modifiers & ModifierKeys.Shift) == ModifierKeys.Shift)
        {
            result |= NativeMethods.MOD_SHIFT;
        }

        if ((modifiers & ModifierKeys.Alt) == ModifierKeys.Alt)
        {
            result |= NativeMethods.MOD_ALT;
        }

        return result;
    }

    private static string FormatHotkey(uint modifiers, uint virtualKey)
    {
        var parts = new List<string>();
        if ((modifiers & NativeMethods.MOD_CONTROL) != 0)
        {
            parts.Add("Ctrl");
        }

        if ((modifiers & NativeMethods.MOD_SHIFT) != 0)
        {
            parts.Add("Shift");
        }

        if ((modifiers & NativeMethods.MOD_ALT) != 0)
        {
            parts.Add("Alt");
        }

        parts.Add(KeyInterop.KeyFromVirtualKey((int)virtualKey).ToString());
        return string.Join("+", parts);
    }
}
