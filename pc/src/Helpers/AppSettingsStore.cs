using System.Text.Json;
using System.IO;

namespace BtInput.Helpers;

public sealed class AppSettings
{
    public bool FirstRunCompleted { get; set; }
    public uint HotkeyModifiers { get; set; } = Constants.DefaultHotkeyModifiers;
    public uint HotkeyVirtualKey { get; set; } = Constants.DefaultHotkeyVirtualKey;
    public bool AutoStartEnabled { get; set; }
    public bool RememberLastDevice { get; set; }
    public ulong? LastDeviceAddress { get; set; }
    public string? LastDeviceName { get; set; }

    public static AppSettings Default => new();
}

public sealed class AppSettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly string _settingsPath;

    public AppSettingsStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var settingsDirectory = Path.Combine(appData, "BtInput");
        _settingsPath = Path.Combine(settingsDirectory, "settings.json");
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return AppSettings.Default;
            }

            var json = File.ReadAllText(_settingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, SerializerOptions) ?? AppSettings.Default;
        }
        catch
        {
            return AppSettings.Default;
        }
    }

    public void Save(AppSettings settings)
    {
        var directory = Path.GetDirectoryName(_settingsPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var json = JsonSerializer.Serialize(settings, SerializerOptions);
        File.WriteAllText(_settingsPath, json);
    }
}
