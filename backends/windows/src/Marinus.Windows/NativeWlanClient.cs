using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Marinus.Windows;

public sealed class WlanException : Exception
{
    public string ContractCode { get; }
    internal WlanException(string code, string message) : base(message) => ContractCode = code;

    internal static WlanException FromWin32(uint code, string operation)
    {
        string category = code switch
        {
            5 => "permission_denied",
            50 or 120 => "unsupported",
            1168 or 1062 or 1722 or 5023 or 0x80342002 => "interface_unavailable",
            _ => "backend_error"
        };
        string advice = code == 5
            ? " Allow location access in Windows Settings > Privacy & security > Location, then run the app from your normal desktop session."
            : "";
        return new WlanException(category, $"{operation} failed: {new Win32Exception(unchecked((int)code)).Message} (Windows error {code}).{advice}");
    }
}

internal sealed class NativeWlanClient : IWlanClient
{
    private readonly SafeWlanHandle _handle;
    private Native.NotificationCallback? _callback;

    internal NativeWlanClient()
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The Native WLAN scanner requires Windows.");
        uint result = Native.WlanOpenHandle(2, IntPtr.Zero, out _, out var handle);
        Check(result, "WlanOpenHandle");
        _handle = new SafeWlanHandle(handle);
    }

    public IReadOnlyList<WirelessInterface> GetInterfaces()
    {
        IntPtr list = IntPtr.Zero;
        try
        {
            Check(Native.WlanEnumInterfaces(_handle, IntPtr.Zero, out list), "WlanEnumInterfaces");
            if (list == IntPtr.Zero) throw new InvalidDataException("Windows returned a missing interface buffer.");
            uint count = unchecked((uint)Marshal.ReadInt32(list));
            if (count > 4096) throw new InvalidDataException("Windows returned an invalid interface count.");
            int size = Marshal.SizeOf<Native.InterfaceInfo>();
            var interfaces = new List<WirelessInterface>();
            for (int index = 0; index < count; index++)
            {
                var info = Marshal.PtrToStructure<Native.InterfaceInfo>(IntPtr.Add(list, 8 + index * size));
                string state = info.State switch
                {
                    0 => "not_ready", 1 => "connected", 2 => "ad_hoc", 3 => "disconnecting",
                    4 => "disconnected", 5 => "associating", 6 => "discovering", 7 => "authenticating", _ => "unknown"
                };
                interfaces.Add(new WirelessInterface(info.Id, info.Description, state));
            }
            return interfaces.OrderBy(item => item.Id).ToArray();
        }
        finally { if (list != IntPtr.Zero) Native.WlanFreeMemory(list); }
    }

    public async Task<DateTimeOffset> RequestScanAsync(Guid id, TimeSpan timeout, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var waiter = new ScanNotificationWaiter(id);
        _callback = (pointer, _) =>
        {
            // No API calls or locks shared with unregister occur in the native callback.
            // Never let an exception cross the unmanaged callback boundary.
            try
            {
                var notification = Marshal.PtrToStructure<Native.NotificationData>(pointer);
                uint? reason = notification.Code == 8 && notification.Data != IntPtr.Zero && notification.DataSize >= 4
                    ? unchecked((uint)Marshal.ReadInt32(notification.Data)) : null;
                waiter.Notify(notification.Source, notification.Code, notification.InterfaceId, reason);
            }
            catch (Exception error) { waiter.Fail(error); }
        };
        Check(Native.WlanRegisterNotification(_handle, 8, false, _callback, IntPtr.Zero, IntPtr.Zero, out _),
            "WlanRegisterNotification");
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var requestedAt = DateTimeOffset.UtcNow;
            waiter.MarkRequested();
            Check(Native.WlanScan(_handle, ref id, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero), "WlanScan");
            uint? failureReason = await waiter.Completion.WaitAsync(timeout, cancellationToken);
            if (failureReason is { } reason)
            {
                var description = new StringBuilder(1024);
                Native.WlanReasonCodeToString(reason, 1024, description, IntPtr.Zero);
                throw new WlanException("backend_error", $"Windows reported scan failure (reason 0x{reason:x8}): {description.ToString().Trim()}");
            }
            return requestedAt;
        }
        finally
        {
            // Unregister waits for in-flight callbacks. Keep the delegate rooted if unregister fails,
            // until Dispose closes the client handle and removes its remaining registrations.
            uint result = Native.WlanRegisterNotification(_handle, 0, false, null, IntPtr.Zero, IntPtr.Zero, out _);
            if (result == 0) _callback = null;
        }
    }

    public IReadOnlyList<BssObservation> ReadBss(Guid id)
    {
        IntPtr list = IntPtr.Zero;
        try
        {
            Check(Native.WlanGetNetworkBssList(_handle, ref id, IntPtr.Zero, 3, false, IntPtr.Zero, out list),
                "WlanGetNetworkBssList");
            return BssParser.Read(list);
        }
        finally { if (list != IntPtr.Zero) Native.WlanFreeMemory(list); }
    }

    public string? ReadConnectedBssid(Guid id)
    {
        IntPtr data = IntPtr.Zero;
        try
        {
            uint result = Native.WlanQueryInterface(_handle, ref id, 7, IntPtr.Zero, out uint size, out data, out _);
            // Connection identity is optional. Disconnection or restricted access must stay unknown.
            if (result != 0 || data == IntPtr.Zero || size < Marshal.SizeOf<Native.ConnectionAttributes>()) return null;
            var connection = Marshal.PtrToStructure<Native.ConnectionAttributes>(data);
            if (connection.State is not (1 or 2)) return null;
            if (connection.Association.Bssid.All(value => value == 0) || connection.Association.Bssid.All(value => value == 255)) return null;
            return string.Join(':', connection.Association.Bssid.Select(value => value.ToString("x2")));
        }
        finally { if (data != IntPtr.Zero) Native.WlanFreeMemory(data); }
    }

    public void Dispose()
    {
        _handle.Dispose();
        GC.KeepAlive(_callback);
    }

    private static void Check(uint result, string operation)
    {
        if (result != 0) throw WlanException.FromWin32(result, operation);
    }
}

internal sealed class ScanNotificationWaiter(Guid interfaceId)
{
    private readonly TaskCompletionSource<uint?> _completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int _requested;
    internal Task<uint?> Completion => _completion.Task;
    internal void MarkRequested() => Volatile.Write(ref _requested, 1);
    internal void Fail(Exception error) => _completion.TrySetException(new InvalidDataException("Invalid Windows scan notification.", error));

    internal void Notify(uint source, uint code, Guid id, uint? failureReason)
    {
        if (Volatile.Read(ref _requested) == 0 || source != 8 || id != interfaceId) return;
        if (code == 7) _completion.TrySetResult(null);
        else if (code == 8) _completion.TrySetResult(failureReason ?? 0);
    }
}

internal static class BssParser
{
    internal static IReadOnlyList<BssObservation> Read(IntPtr list)
    {
        if (list == IntPtr.Zero) throw new InvalidDataException("Windows returned a missing BSS buffer.");
        uint totalSize = unchecked((uint)Marshal.ReadInt32(list));
        uint count = unchecked((uint)Marshal.ReadInt32(list, 4));
        int stride = Marshal.SizeOf<Native.BssEntry>();
        if (totalSize < 8 || totalSize > int.MaxValue || 8UL + (ulong)count * (uint)stride > totalSize)
            throw new InvalidDataException("Windows returned a truncated BSS buffer.");
        var entries = new List<BssObservation>();
        for (int index = 0; index < count; index++)
        {
            var native = Marshal.PtrToStructure<Native.BssEntry>(IntPtr.Add(list, 8 + index * stride));
            if (native.Ssid.Length > 32) throw new InvalidDataException("Windows returned an SSID longer than 32 bytes.");
            entries.Add(new BssObservation(native.Ssid.Bytes[..(int)native.Ssid.Length], native.Bssid,
                native.Rssi, native.LinkQuality, native.CenterFrequencyKhz, native.HostTimestamp));
        }
        return entries;
    }
}

internal sealed class SafeWlanHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    internal SafeWlanHandle(IntPtr value) : base(true) => SetHandle(value);
    protected override bool ReleaseHandle() => Native.WlanCloseHandle(handle, IntPtr.Zero) == 0;
}

internal static class Native
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct InterfaceInfo
    {
        public Guid Id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Description;
        public uint State;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Ssid
    {
        public uint Length;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Bytes;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct RateSet
    {
        public uint Length;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 126)] public ushort[] Rates;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct BssEntry
    {
        public Ssid Ssid;
        public uint PhyId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 6)] public byte[] Bssid;
        public uint BssType;
        public uint PhyType;
        public int Rssi;
        public uint LinkQuality;
        public byte InRegDomain;
        public ushort BeaconPeriod;
        public ulong Timestamp;
        public ulong HostTimestamp;
        public ushort CapabilityInformation;
        public uint CenterFrequencyKhz;
        public RateSet Rates;
        public uint IeOffset;
        public uint IeSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct AssociationAttributes
    {
        public Ssid Ssid;
        public uint BssType;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 6)] public byte[] Bssid;
        public uint PhyType;
        public uint PhyIndex;
        public uint SignalQuality;
        public uint RxRate;
        public uint TxRate;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct ConnectionAttributes
    {
        public uint State;
        public uint Mode;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string ProfileName;
        public AssociationAttributes Association;
        public uint SecurityEnabled;
        public uint OneXEnabled;
        public uint AuthAlgorithm;
        public uint CipherAlgorithm;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NotificationData
    {
        public uint Source;
        public uint Code;
        public Guid InterfaceId;
        public uint DataSize;
        public IntPtr Data;
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    internal delegate void NotificationCallback(IntPtr notification, IntPtr context);

    [DllImport("wlanapi.dll")]
    internal static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanEnumInterfaces(SafeWlanHandle handle, IntPtr reserved, out IntPtr list);
    [DllImport("wlanapi.dll")]
    internal static extern void WlanFreeMemory(IntPtr memory);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanScan(SafeWlanHandle handle, ref Guid id, IntPtr ssid, IntPtr ies, IntPtr reserved);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanGetNetworkBssList(SafeWlanHandle handle, ref Guid id, IntPtr ssid, uint type,
        [MarshalAs(UnmanagedType.Bool)] bool securityEnabled, IntPtr reserved, out IntPtr list);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanQueryInterface(SafeWlanHandle handle, ref Guid id, uint opcode, IntPtr reserved,
        out uint size, out IntPtr data, out uint valueType);
    [DllImport("wlanapi.dll")]
    internal static extern uint WlanRegisterNotification(SafeWlanHandle handle, uint source,
        [MarshalAs(UnmanagedType.Bool)] bool ignoreDuplicate, NotificationCallback? callback,
        IntPtr context, IntPtr reserved, out uint previousSource);
    [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)]
    internal static extern uint WlanReasonCodeToString(uint reason, uint size, StringBuilder buffer, IntPtr reserved);
}
