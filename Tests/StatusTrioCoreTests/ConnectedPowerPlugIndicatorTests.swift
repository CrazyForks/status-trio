import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

/// The arc's top gap carries either the charging bolt or, for a connected power
/// source that is not charging, a plug. Menu bar and Dock share the renderer, so
/// both are asserted here.
@MainActor
final class ConnectedPowerPlugIndicatorTests: XCTestCase {
    private let glyphRegion = CGRect(x: 45, y: 0, width: 30, height: 30)
    private let arcRegion = CGRect(x: 0, y: 40, width: 120, height: 80)

    func testMenuBarIconDrawsAPlugForConnectedPowerWhenEnabled() throws {
        let bolt = try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: false)
        )
        let plug = try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: true)
        )

        XCTAssertGreaterThan(bolt.alphaSum(inSVGRect: glyphRegion, size: 20, scale: 8), 0)
        XCTAssertGreaterThan(plug.alphaSum(inSVGRect: glyphRegion, size: 20, scale: 8), 0)
        XCTAssertNotEqual(bolt.bytes, plug.bytes)
    }

    func testPlugOptionChangesOnlyTheGlyphAndNotTheArc() throws {
        let bolt = try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: false)
        )
        let plug = try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: true)
        )

        // The gap width must not move between the two states, so everything
        // outside the top gap stays pixel-identical.
        XCTAssertEqual(
            bolt.alphaSum(inSVGRect: arcRegion, size: 20, scale: 8),
            plug.alphaSum(inSVGRect: arcRegion, size: 20, scale: 8)
        )
    }

    func testMenuBarIconKeepsTheBoltWhileCharging() throws {
        let withoutPlug = try menuBarPixels(
            for: chargingBattery(),
            options: batteryOptions(showsPlug: false)
        )
        let withPlug = try menuBarPixels(
            for: chargingBattery(),
            options: batteryOptions(showsPlug: true)
        )

        XCTAssertEqual(withoutPlug.bytes, withPlug.bytes)
    }

    func testMenuBarIconDropsTheIndicatorWhenItIsDisabled() throws {
        let hidden = try menuBarPixels(
            for: connectedBattery(),
            options: BatteryIconOptions(
                showsPercentage: true,
                showsChargingIndicator: false,
                usesStatusColors: true,
                criticalThreshold: 20,
                showsPlugForConnectedPower: true
            )
        )
        let plug = try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: true)
        )

        XCTAssertNotEqual(hidden.bytes, plug.bytes)
    }

    func testDockIconFollowsThePlugOption() throws {
        let bolt = try dockPixels(
            for: MenuBarStatus(snapshot: snapshot(for: connectedBattery())),
            options: batteryOptions(showsPlug: false)
        )
        let plug = try dockPixels(
            for: MenuBarStatus(snapshot: snapshot(for: connectedBattery())),
            options: batteryOptions(showsPlug: true)
        )

        XCTAssertNotEqual(bolt.bytes, plug.bytes)
    }

    func testPlugGlyphIsNotSmallerThanTheBolt() throws {
        let bolt = try XCTUnwrap(topGapInk(in: try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: false)
        )))
        let plug = try XCTUnwrap(topGapInk(in: try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: true)
        )))

        XCTAssertGreaterThan(
            plug.height,
            bolt.height,
            "the plug reads smaller than the bolt because its strokes are thinner"
        )
    }

    func testPlugGlyphStaysInsideTheTopGap() throws {
        let plug = try XCTUnwrap(topGapInk(in: try menuBarPixels(
            for: connectedBattery(),
            options: batteryOptions(showsPlug: true)
        )))

        XCTAssertGreaterThan(plug.minY, 0, "the plug must not clip at the top of the bitmap")
        XCTAssertLessThan(plug.maxY, 54, "the plug must stay clear of the Wi-Fi glyph")
        XCTAssertGreaterThan(plug.minX, 56, "the plug must stay clear of the arc")
        XCTAssertLessThan(plug.maxX, 104, "the plug must stay clear of the arc")
    }

    func testDockRenderKeyFollowsThePlugOption() {
        let status = MenuBarStatus(snapshot: snapshot(for: connectedBattery()))
        let bolt = DockIconRenderKey(
            status: status,
            options: batteryOptions(showsPlug: false),
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let plug = DockIconRenderKey(
            status: status,
            options: batteryOptions(showsPlug: true),
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        XCTAssertEqual(bolt.topIndicator, .bolt)
        XCTAssertEqual(plug.topIndicator, .plug)
        XCTAssertNotEqual(bolt, plug)
    }

    func testDockRenderKeyDistinguishesChargingFromConnectedPower() {
        let charging = DockIconRenderKey(
            status: MenuBarStatus(snapshot: snapshot(for: chargingBattery())),
            options: batteryOptions(showsPlug: true),
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let connected = DockIconRenderKey(
            status: MenuBarStatus(snapshot: snapshot(for: connectedBattery())),
            options: batteryOptions(showsPlug: true),
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        XCTAssertEqual(charging.topIndicator, .bolt)
        XCTAssertEqual(connected.topIndicator, .plug)
    }

    private func batteryOptions(showsPlug: Bool) -> BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: true,
            showsChargingIndicator: true,
            usesStatusColors: true,
            criticalThreshold: 20,
            showsPlugForConnectedPower: showsPlug
        )
    }

    private func connectedBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: false,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func chargingBattery() -> BatteryStatus {
        BatteryStatus(
            rawPercentage: 76,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: false,
            isConnectedToPower: true
        )
    }

    private func snapshot(for battery: BatteryStatus) -> StatusSnapshot {
        StatusSnapshot(battery: battery, wifi: .placeholder, volume: .placeholder)
    }

    private struct InkBounds {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int

        var height: Int { maxY - minY + 1 }
    }

    /// Ink of the top-gap glyph alone: the window sits inside the arc's gap and
    /// above the Wi-Fi glyph drawn inside the arc.
    private func topGapInk(in pixels: PixelBuffer) -> InkBounds? {
        var points: [(x: Int, y: Int)] = []
        for y in 0..<min(54, pixels.height) {
            for x in 56..<min(104, pixels.width) where pixels.rgba(x: x, y: y).alpha > 120 {
                points.append((x, y))
            }
        }
        guard let first = points.first else { return nil }

        return points.dropFirst().reduce(
            InkBounds(minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { bounds, point in
            InkBounds(
                minX: min(bounds.minX, point.x),
                maxX: max(bounds.maxX, point.x),
                minY: min(bounds.minY, point.y),
                maxY: max(bounds.maxY, point.y)
            )
        }
    }

    private func menuBarPixels(
        for battery: BatteryStatus,
        options: BatteryIconOptions
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(StatusIconRenderer.render(
            snapshot: snapshot(for: battery),
            size: 20,
            scale: 8,
            foreground: CGColor(gray: 1, alpha: 1),
            options: options
        ))
        return try PixelBuffer(image: image)
    }

    private func dockPixels(
        for status: MenuBarStatus,
        options: BatteryIconOptions
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(
            status: status,
            options: options,
            backgroundStyle: .dark
        ))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try XCTUnwrap(representation.cgImage))
    }
}
