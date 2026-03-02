using System.Diagnostics;
using System.Text;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Foundation;
using Windows.Storage.Streams;
using BtInput.Helpers;

namespace BtInput.Core;

public sealed class BleManager : IAsyncDisposable
{
    private readonly Guid _serviceGuid = Guid.Parse(Constants.BleServiceUuid);
    private readonly Guid _textGuid = Guid.Parse(Constants.TextCharacteristicUuid);
    private readonly Guid _controlGuid = Guid.Parse(Constants.ControlCharacteristicUuid);
    private readonly Guid _statusGuid = Guid.Parse(Constants.StatusCharacteristicUuid);

    private BluetoothLEAdvertisementWatcher? _watcher;
    private BluetoothLEDevice? _device;
    private GattDeviceService? _service;
    private GattCharacteristic? _textCharacteristic;
    private GattCharacteristic? _statusCharacteristic;
    private GattCharacteristic? _controlCharacteristic;
    private ulong? _lastBluetoothAddress;
    private bool _userInitiatedDisconnect;

    public event Action<byte[]>? TextDataReceived;
    public event Action<byte[]>? StatusDataReceived;
    public event Action<bool>? ConnectionChanged;
    public event Action<ulong, string>? DeviceDiscovered;

    public bool IsConnected => _device?.ConnectionStatus == BluetoothConnectionStatus.Connected;

    public string ConnectedDeviceName => _device?.Name ?? string.Empty;

    public ulong ConnectedDeviceAddress => _device?.BluetoothAddress ?? _lastBluetoothAddress ?? 0;

    public async Task StartScanAsync()
    {
        StopScan();

        _watcher = new BluetoothLEAdvertisementWatcher
        {
            ScanningMode = BluetoothLEScanningMode.Active
        };

        _watcher.Received += OnAdvertisementReceived;
        _watcher.Stopped += OnWatcherStopped;
        _watcher.Start();

        using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, timeoutCts.Token);
        }
        catch (TaskCanceledException)
        {
            StopScan();
        }
    }

    public async Task ConnectAsync(ulong bluetoothAddress)
    {
        _lastBluetoothAddress = bluetoothAddress;
        _userInitiatedDisconnect = false;

        StopScan();
        await CleanupConnectionAsync();

        _device = await BluetoothLEDevice.FromBluetoothAddressAsync(bluetoothAddress);
        if (_device is null)
        {
            throw new InvalidOperationException("Failed to create BluetoothLEDevice.");
        }

        _device.ConnectionStatusChanged += OnConnectionStatusChanged;

        var serviceResult = await _device.GetGattServicesForUuidAsync(_serviceGuid, BluetoothCacheMode.Uncached);
        if (serviceResult.Status != GattCommunicationStatus.Success || serviceResult.Services.Count == 0)
        {
            throw new InvalidOperationException("Target GATT service not found.");
        }

        _service = serviceResult.Services[0];
        var session = await GattSession.FromDeviceIdAsync(_device.BluetoothDeviceId);
        if (session is not null)
        {
            session.MaintainConnection = true;
            Debug.WriteLine($"Gatt MaxPduSize: {session.MaxPduSize}");
        }

        await BindCharacteristicsAsync();
        ConnectionChanged?.Invoke(true);
    }

    public async Task SendControlAsync(byte[] data)
    {
        if (_controlCharacteristic is null)
        {
            Debug.WriteLine("SendControlAsync skipped: control characteristic is null");
            return;
        }

        var writer = new DataWriter();
        writer.WriteBytes(data);
        var status = await _controlCharacteristic.WriteValueAsync(
            writer.DetachBuffer(),
            GattWriteOption.WriteWithResponse);

        if (status != GattCommunicationStatus.Success)
        {
            throw new InvalidOperationException($"Control write failed: {status}");
        }

        Debug.WriteLine($"Control message sent: {Encoding.UTF8.GetString(data)}");
    }

    public async Task DisconnectAsync()
    {
        _userInitiatedDisconnect = true;
        await CleanupConnectionAsync();
        ConnectionChanged?.Invoke(false);
    }

    private async Task BindCharacteristicsAsync()
    {
        if (_service is null)
        {
            return;
        }

        var allCharacteristicsResult = await _service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached);
        if (allCharacteristicsResult.Status != GattCommunicationStatus.Success)
        {
            throw new InvalidOperationException("Unable to enumerate service characteristics.");
        }

        foreach (var characteristic in allCharacteristicsResult.Characteristics)
        {
            if (characteristic.Uuid == _textGuid)
            {
                _textCharacteristic = characteristic;
            }
            else if (characteristic.Uuid == _statusGuid)
            {
                _statusCharacteristic = characteristic;
            }
            else if (characteristic.Uuid == _controlGuid)
            {
                _controlCharacteristic = characteristic;
            }
        }

        if (_textCharacteristic is null || _statusCharacteristic is null || _controlCharacteristic is null)
        {
            throw new InvalidOperationException("Not all required characteristics were discovered.");
        }

        _textCharacteristic.ValueChanged += OnTextValueChanged;
        _statusCharacteristic.ValueChanged += OnStatusValueChanged;

        await _textCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
            GattClientCharacteristicConfigurationDescriptorValue.Notify);
        await _statusCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
            GattClientCharacteristicConfigurationDescriptorValue.Notify);
    }

    private void OnAdvertisementReceived(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args)
    {
        bool hasService = args.Advertisement.ServiceUuids.Any(uuid => uuid == _serviceGuid);
        if (!hasService)
        {
            return;
        }

        var name = string.IsNullOrWhiteSpace(args.Advertisement.LocalName) ? "Unknown" : args.Advertisement.LocalName;
        DeviceDiscovered?.Invoke(args.BluetoothAddress, name);
    }

    private void OnWatcherStopped(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs args)
    {
        Debug.WriteLine($"BLE watcher stopped: {args.Error}");
    }

    private void OnTextValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
    {
        try
        {
            TextDataReceived?.Invoke(ReadBytes(args.CharacteristicValue));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"OnTextValueChanged failed: {ex.Message}");
        }
    }

    private void OnStatusValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
    {
        try
        {
            StatusDataReceived?.Invoke(ReadBytes(args.CharacteristicValue));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"OnStatusValueChanged failed: {ex.Message}");
        }
    }

    private async void OnConnectionStatusChanged(BluetoothLEDevice sender, object args)
    {
        if (sender.ConnectionStatus == BluetoothConnectionStatus.Connected)
        {
            ConnectionChanged?.Invoke(true);
            return;
        }

        ConnectionChanged?.Invoke(false);
        if (_userInitiatedDisconnect)
        {
            return;
        }

        await TryReconnectWithBackoffAsync();
    }

    private async Task TryReconnectWithBackoffAsync()
    {
        if (_lastBluetoothAddress is null)
        {
            return;
        }

        var delays = new[] { 1, 2, 4, 8, 16 };
        foreach (var seconds in delays)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(seconds));
                await ConnectAsync(_lastBluetoothAddress.Value);

                var syncRequest = Encoding.UTF8.GetBytes("{\"t\":131}");
                await SendControlAsync(syncRequest);
                return;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Reconnect attempt failed: {ex.Message}");
            }
        }
    }

    private static byte[] ReadBytes(IBuffer buffer)
    {
        var reader = DataReader.FromBuffer(buffer);
        var bytes = new byte[buffer.Length];
        reader.ReadBytes(bytes);
        return bytes;
    }

    private void StopScan()
    {
        if (_watcher is null)
        {
            return;
        }

        _watcher.Received -= OnAdvertisementReceived;
        _watcher.Stopped -= OnWatcherStopped;

        if (_watcher.Status == BluetoothLEAdvertisementWatcherStatus.Started ||
            _watcher.Status == BluetoothLEAdvertisementWatcherStatus.Created)
        {
            _watcher.Stop();
        }

        _watcher = null;
    }

    private async Task CleanupConnectionAsync()
    {
        if (_textCharacteristic is not null)
        {
            _textCharacteristic.ValueChanged -= OnTextValueChanged;
            await _textCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.None);
        }

        if (_statusCharacteristic is not null)
        {
            _statusCharacteristic.ValueChanged -= OnStatusValueChanged;
            await _statusCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.None);
        }

        _textCharacteristic = null;
        _statusCharacteristic = null;
        _controlCharacteristic = null;

        _service?.Dispose();
        _service = null;

        if (_device is not null)
        {
            _device.ConnectionStatusChanged -= OnConnectionStatusChanged;
            _device.Dispose();
            _device = null;
        }
    }

    public async ValueTask DisposeAsync()
    {
        StopScan();
        await CleanupConnectionAsync();
    }
}