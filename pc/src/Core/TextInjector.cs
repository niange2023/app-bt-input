using System.Windows;
using System.Diagnostics;
using BtInput.Helpers;
using BtInput.Protocol;

namespace BtInput.Core;

public interface IInputSender
{
    void SendUnicodeText(string text);
    void SendVirtualKey(ushort virtualKey);
    void SendShortcut(ushort modifier, ushort key);
}

public interface IClipboardService
{
    bool HasText();
    System.Windows.IDataObject? GetDataObject();
    void SetText(string text);
    void Restore(System.Windows.IDataObject dataObject);
}

public sealed class WpfClipboardService : IClipboardService
{
    public bool HasText()
    {
        return System.Windows.Clipboard.ContainsData(System.Windows.DataFormats.UnicodeText) ||
               System.Windows.Clipboard.ContainsText();
    }

    public System.Windows.IDataObject? GetDataObject()
    {
        return System.Windows.Clipboard.GetDataObject();
    }

    public void SetText(string text)
    {
        System.Windows.Clipboard.SetText(text);
    }

    public void Restore(System.Windows.IDataObject dataObject)
    {
        System.Windows.Clipboard.SetDataObject(dataObject);
    }
}

public sealed class NativeInputSender : IInputSender
{
    public void SendUnicodeText(string text)
    {
        foreach (var character in text)
        {
            var keyDown = new NativeMethods.INPUT
            {
                type = NativeMethods.INPUT_KEYBOARD,
                U = new NativeMethods.InputUnion
                {
                    ki = new NativeMethods.KEYBDINPUT
                    {
                        wScan = character,
                        dwFlags = NativeMethods.KEYEVENTF_UNICODE
                    }
                }
            };

            var keyUp = new NativeMethods.INPUT
            {
                type = NativeMethods.INPUT_KEYBOARD,
                U = new NativeMethods.InputUnion
                {
                    ki = new NativeMethods.KEYBDINPUT
                    {
                        wScan = character,
                        dwFlags = NativeMethods.KEYEVENTF_UNICODE | NativeMethods.KEYEVENTF_KEYUP
                    }
                }
            };

            NativeMethods.SendInput(2, new[] { keyDown, keyUp }, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>());
        }
    }

    public void SendVirtualKey(ushort virtualKey)
    {
        var keyDown = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = virtualKey,
                    dwFlags = 0
                }
            }
        };

        var keyUp = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT
                {
                    wVk = virtualKey,
                    dwFlags = NativeMethods.KEYEVENTF_KEYUP
                }
            }
        };

        NativeMethods.SendInput(2, new[] { keyDown, keyUp }, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>());
    }

    public void SendShortcut(ushort modifier, ushort key)
    {
        var downModifier = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT { wVk = modifier }
            }
        };
        var downKey = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT { wVk = key }
            }
        };
        var upKey = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT { wVk = key, dwFlags = NativeMethods.KEYEVENTF_KEYUP }
            }
        };
        var upModifier = new NativeMethods.INPUT
        {
            type = NativeMethods.INPUT_KEYBOARD,
            U = new NativeMethods.InputUnion
            {
                ki = new NativeMethods.KEYBDINPUT { wVk = modifier, dwFlags = NativeMethods.KEYEVENTF_KEYUP }
            }
        };

        NativeMethods.SendInput(4, new[] { downModifier, downKey, upKey, upModifier }, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>());
    }
}

public sealed class TextInjector
{
    private readonly IInputSender _inputSender;
    private readonly IClipboardService _clipboardService;

    public TextInjector(IInputSender? inputSender = null, IClipboardService? clipboardService = null)
    {
        _inputSender = inputSender ?? new NativeInputSender();
        _clipboardService = clipboardService ?? new WpfClipboardService();
    }

    public void InjectText(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        if (text.Length <= 10)
        {
            try
            {
                _inputSender.SendUnicodeText(text);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"SendInput unicode failed: {ex.Message}");
            }
            return;
        }

        ClipboardInject(text);
    }

    public void InjectBackspace(int count)
    {
        for (var index = 0; index < count; index++)
        {
            try
            {
                _inputSender.SendVirtualKey(NativeMethods.VK_BACK);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Backspace injection failed: {ex.Message}");
                break;
            }
        }
    }

    public void InjectFullSync(string fullText)
    {
        _inputSender.SendShortcut(NativeMethods.VK_CONTROL, 0x41);
        ClipboardInject(fullText);
    }

    public void HandleDelta(TextDeltaMessage message)
    {
        if (message.Op == DeltaOp.Append)
        {
            InjectText(message.Text);
            return;
        }

        if (message.Op == DeltaOp.Delete)
        {
            InjectBackspace(message.DeleteCount);
            return;
        }

        if (message.ClipboardHint)
        {
            ClipboardInject(message.Text);
            return;
        }

        InjectFullSync(message.Text);
    }

    private void ClipboardInject(string text)
    {
        System.Windows.IDataObject? originalClipboard = null;

        try
        {
            if (_clipboardService.HasText())
            {
                originalClipboard = _clipboardService.GetDataObject();
            }

            _clipboardService.SetText(text);
            _inputSender.SendShortcut(NativeMethods.VK_CONTROL, 0x56);
            Thread.Sleep(50);
        }
        catch
        {
            Debug.WriteLine("Clipboard injection failed, fallback to unicode send.");
            _inputSender.SendUnicodeText(text);
        }
        finally
        {
            if (originalClipboard is not null)
            {
                try
                {
                    _clipboardService.Restore(originalClipboard);
                }
                catch
                {
                    // keep latest clipboard data when restore fails
                }
            }
        }
    }
}
