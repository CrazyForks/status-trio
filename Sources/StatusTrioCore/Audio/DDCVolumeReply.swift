import Foundation

struct DDCVolumeReply: Equatable, Sendable {
    let current: UInt16
    let maximum: UInt16

    var scalar: Double {
        Double(current) / Double(maximum)
    }

    static func decode(_ bytes: [UInt8]) -> Self? {
        guard bytes.count == 11,
              bytes[0] == 0x6E,
              bytes[1] == 0x88,
              bytes[2] == 0x02,
              bytes[3] == 0,
              bytes[4] == 0x62,
              bytes.prefix(10).reduce(UInt8(0x50), ^) == bytes[10]
        else {
            return nil
        }

        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        guard maximum > 0, current <= maximum else { return nil }

        return Self(current: current, maximum: maximum)
    }

    func targetValue(for scalar: Double) -> UInt16 {
        guard scalar.isFinite else { return current }
        return UInt16((min(1, max(0, scalar)) * Double(maximum)).rounded())
    }
}
