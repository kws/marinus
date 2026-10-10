namespace Marinus.Windows;

// Decode operation elements, not the AP's maximum PHY capabilities. The element
// layouts are defined by IEEE 802.11; HE/EHT optional-field flags and width codes
// are also documented in include/linux/ieee80211-{he,eht}.h and iw's util.c.
internal static class AdvertisedChannelWidth
{
    internal static int? Read(ReadOnlySpan<byte> ies, uint frequencyKhz)
    {
        ReadOnlySpan<byte> ht = [], vht = [], he = [], eht = [];
        while (!ies.IsEmpty)
        {
            if (ies.Length < 2 || ies[1] > ies.Length - 2) return null;
            byte id = ies[0];
            var data = ies.Slice(2, ies[1]);
            ies = ies[(2 + data.Length)..];
            switch (id)
            {
                case 61: // HT Operation
                    if (data.Length != 22 || !ht.IsEmpty) return null;
                    ht = data;
                    break;
                case 192: // VHT Operation
                    if (data.Length != 5 || !vht.IsEmpty) return null;
                    vht = data;
                    break;
                case 255: // Element ID Extension
                    if (data.IsEmpty) return null;
                    if (data[0] == 36) // HE Operation
                    {
                        if (data.Length < 7 || !he.IsEmpty) return null;
                        he = data[1..];
                    }
                    else if (data[0] == 106) // EHT Operation
                    {
                        if (data.Length < 6 || !eht.IsEmpty) return null;
                        eht = data[1..];
                    }
                    break;
            }
        }

        bool sixGHz = frequencyKhz is >= 5925000 and <= 7125000;
        if (!eht.IsEmpty && (eht[0] & 3) == 2) return null; // A bitmap requires operation info.
        if (!eht.IsEmpty && (eht[0] & 1) != 0)
        {
            int required = (eht[0] & 2) != 0 ? 10 : 8;
            if (eht.Length < required) return null;
            int code = eht[5] & 7;
            // 320 MHz operation is only defined in the 6 GHz band.
            return code <= 4 && (code != 4 || sixGHz) ? 20 << code : null;
        }

        int? htWidth = null;
        if (!ht.IsEmpty)
        {
            int secondary = ht[1] & 3;
            if (secondary != 2)
                htWidth = (ht[1] & 4) != 0 && secondary != 0 ? 40 : 20;
        }
        if (!he.IsEmpty)
        {
            bool hasVht = (he[1] & 0x40) != 0;
            int sixOffset = 6 + (hasVht ? 3 : 0) + ((he[1] & 0x80) != 0 ? 1 : 0);
            bool hasSix = (he[2] & 2) != 0;
            if (he.Length < sixOffset + (hasSix ? 5 : 0)) return null;
            if (sixGHz)
            {
                if (!hasSix) return null;
                var operation = he.Slice(sixOffset, 5);
                int code = operation[1] & 3;
                // A non-contiguous 80+80 MHz channel cannot be represented by
                // this contract's single width, so retain unknown in that case.
                if (operation[2] == 0) return null;
                return code < 3 ? 20 << code
                    : operation[3] == 0 || Math.Abs(operation[3] - operation[2]) == 8 ? 160 : null;
            }
            if (hasVht) return VhtWidth(he.Slice(6, 3), htWidth);
        }
        if (sixGHz) return null; // No legacy-width guess for 6 GHz observations.
        return !vht.IsEmpty ? VhtWidth(vht, htWidth) : htWidth;
    }

    private static int? VhtWidth(ReadOnlySpan<byte> operation, int? htWidth) => operation[0] switch
    {
        0 => htWidth, // VHT delegates 20/40 MHz operation to HT.
        1 when operation[1] != 0 && operation[2] == 0 => 80,
        1 when operation[1] != 0 && Math.Abs(operation[2] - operation[1]) == 8 => 160,
        2 when operation[1] != 0 => 160, // Original VHT 160 MHz encoding.
        _ => null // Missing segments, reserved codes and 80+80 MHz.
    };
}
