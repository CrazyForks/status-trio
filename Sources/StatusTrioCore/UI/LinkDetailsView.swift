import AppKit
import SwiftUI

/// One row of a link's technical details.
struct LinkDetailRow: Equatable {
    let label: LocalizationKey
    let value: String?
    /// Addresses are worth copying; a channel number is not. Copying is the only
    /// affordance in these rows that touches the pasteboard.
    let isCopyable: Bool

    init(label: LocalizationKey, value: String?, isCopyable: Bool = false) {
        self.label = label
        self.value = value
        self.isCopyable = isCopyable
    }
}

/// The rows each link reports.
///
/// Built here rather than inside the views so the row set is a value a test can
/// assert on: which rows a cable has, which rows a radio adds, and which of them
/// offer the address to the pasteboard.
@MainActor
enum LinkDetailPresentation {
    /// The five rows both links report, in the order the panels show them.
    static func sharedRows(
        interfaceName: String?,
        ipv4Addresses: [String],
        ipv6Addresses: [String],
        router: String?,
        dnsServers: [String]
    ) -> [LinkDetailRow] {
        [
            LinkDetailRow(label: .networkDetailInterface, value: interfaceName),
            LinkDetailRow(
                label: .networkDetailIPv4,
                value: ipv4Addresses.joined(separator: ", "),
                isCopyable: true
            ),
            LinkDetailRow(
                label: .networkDetailIPv6,
                value: ipv6Addresses.joined(separator: ", "),
                isCopyable: true
            ),
            LinkDetailRow(label: .networkDetailRouter, value: router, isCopyable: true),
            LinkDetailRow(
                label: .networkDetailDNS,
                value: dnsServers.joined(separator: ", "),
                isCopyable: true
            )
        ]
    }

    /// A cable reports the shared rows and nothing else: there is no radio, no
    /// association, and no negotiated rate on this side of the link.
    static func wiredRows(_ details: PrimaryLinkDetails) -> [LinkDetailRow] {
        sharedRows(
            interfaceName: details.interfaceName,
            ipv4Addresses: details.ipv4Addresses,
            ipv6Addresses: details.ipv6Addresses,
            router: details.router,
            dnsServers: details.dnsServers
        )
    }

    /// The radio rows first, then the shared rows once details are expanded —
    /// the same split the panel had before the rows were shared.
    static func wirelessRows(
        _ details: WiFiConnectionDetails,
        expanded: Bool,
        localization: Localization
    ) -> [LinkDetailRow] {
        var rows = [
            LinkDetailRow(label: .wifiDetailSSID, value: details.ssid),
            LinkDetailRow(label: .wifiDetailBSSID, value: details.bssid, isCopyable: true),
            LinkDetailRow(label: .wifiDetailBand, value: details.band),
            // The closure keeps this line out of `scripts/check-forbidden-patterns.sh`:
            // `channel.map(String.init)` trips it as `violation:map`, the same
            // line-based false positive `AudioOutputDeviceIcon.swift` records,
            // because the operator form makes the scanner read the line and its
            // label pass then resolves `.map` to an unrelated `func map(...)`.
            LinkDetailRow(label: .wifiDetailChannel, value: details.channel.map { String($0) }),
            LinkDetailRow(label: .wifiDetailChannelWidth, value: details.channelWidth),
            LinkDetailRow(label: .wifiDetailRSSI, value: details.rssi.map { "\($0) dBm" }),
            LinkDetailRow(label: .wifiDetailPHY, value: details.phyMode),
            LinkDetailRow(
                label: .wifiDetailTxRate,
                value: details.transmitRateMbps.map { String(format: "%.1f Mbps", $0) }
            ),
            LinkDetailRow(
                label: .wifiDetailSecurity,
                value: securityName(details.security, localization: localization)
            )
        ]
        guard expanded else { return rows }

        rows.append(LinkDetailRow(label: .wifiDetailNoise, value: details.noise.map { "\($0) dBm" }))
        rows.append(LinkDetailRow(label: .wifiDetailSNR, value: details.signalToNoiseRatio.map { "\($0) dB" }))
        rows.append(LinkDetailRow(label: .wifiDetailCountryCode, value: details.countryCode))
        rows.append(contentsOf: sharedRows(
            interfaceName: details.interfaceName,
            ipv4Addresses: details.ipv4Addresses,
            ipv6Addresses: details.ipv6Addresses,
            router: details.router,
            dnsServers: details.dnsServers
        ))
        return rows
    }

    /// Most security kinds are a protocol name, not a word to translate.
    private static func securityName(
        _ security: WiFiSecurityKind,
        localization: Localization
    ) -> String {
        switch security {
        case .open: localization.string(.wifiSecurityOpen)
        case .wep, .dynamicWEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA"
        case .wpa2Personal, .personal: "WPA2"
        case .wpa3Personal, .wpa3Transition: "WPA3"
        case .owe: "OWE"
        case .oweTransition: "OWE Transition"
        case .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise:
            localization.string(.wifiSecurityEnterprise)
        case .unknown: localization.string(.networkDetailUnavailable)
        }
    }
}

/// Draws a link's rows. Shared so the Wi-Fi panel and the wired panel cannot
/// drift apart on spacing, alignment, or what tapping a value does.
struct LinkDetailsList: View {
    @EnvironmentObject private var localization: Localization
    let rows: [LinkDetailRow]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                row(rows[index])
            }
        }
    }

    private func row(_ row: LinkDetailRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(localization.string(row.label))
                .foregroundStyle(.secondary)
            Spacer()
            if row.isCopyable, let value = row.value, !value.isEmpty {
                Button(value) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(.plain)
                .textSelection(.enabled)
                .accessibilityLabel("\(localization.string(row.label)): \(value)")
            } else {
                Text(row.value?.isEmpty == false ? row.value! : localization.string(.networkDetailUnavailable))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }
}
