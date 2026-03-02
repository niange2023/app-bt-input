using System.Diagnostics;

namespace BtInput.Helpers;

public sealed class PcStabilityMonitor : IDisposable
{
    private readonly DebugFileLogger _logger;
    private readonly System.Timers.Timer _timer;

    public PcStabilityMonitor(DebugFileLogger logger)
    {
        _logger = logger;
        _timer = new System.Timers.Timer(60_000);
        _timer.Elapsed += (_, _) => SampleMemory();
    }

    public int SyncRequestCount { get; private set; }

    public void Start()
    {
        _timer.Start();
        SampleMemory();
    }

    public void RecordReceivedMessage(int bytes, string summary)
    {
        _logger.Log($"RX message bytes={bytes} summary={summary}");
    }

    public void RecordSyncRequestSent()
    {
        SyncRequestCount++;
        _logger.Log($"SYNC_REQUEST sent count={SyncRequestCount}");
    }

    public void SampleMemory()
    {
        var workingSetMb = Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        _logger.Log($"Memory workingSetMB={workingSetMb:F2}");
    }

    public void Dispose()
    {
        _timer.Stop();
        _timer.Dispose();
    }
}
