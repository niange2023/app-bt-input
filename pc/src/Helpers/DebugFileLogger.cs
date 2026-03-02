using System.IO;

namespace BtInput.Helpers;

public sealed class DebugFileLogger
{
    private readonly string _logPath;
    private readonly object _syncLock = new();

    public DebugFileLogger(bool enabled)
    {
        IsEnabled = enabled;
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var directory = Path.Combine(appData, "BtInput");
        Directory.CreateDirectory(directory);
        _logPath = Path.Combine(directory, "debug.log");
    }

    public bool IsEnabled { get; set; }

    public void Log(string message)
    {
        if (!IsEnabled)
        {
            return;
        }

        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}";
        lock (_syncLock)
        {
            File.AppendAllText(_logPath, line);
        }
    }
}
