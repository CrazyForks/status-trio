import AppKit
import XCTest
@testable import StatusTrioCore

final class DockIconRendererTests: XCTestCase {
    func testDockIconHasExpectedLogicalAndPixelSize() throws {
        let image = try XCTUnwrap(DockIconRenderer.image(status: .placeholder))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )

        XCTAssertEqual(image.size, NSSize(width: 512, height: 512))
        XCTAssertEqual(representation.pixelsWide, 1024)
        XCTAssertEqual(representation.pixelsHigh, 1024)
        XCTAssertFalse(image.isTemplate)
    }

    func testDockIconKeepsTransparentMarginAndDarkBody() throws {
        let pixels = try pixels(for: .placeholder)
        let corner = pixels.rgba(x: 0, y: 0)
        let margin = pixels.rgba(x: 512, y: 8)
        let body = pixels.rgba(x: 120, y: 512)

        XCTAssertEqual(corner.alpha, 0)
        XCTAssertEqual(margin.alpha, 0)
        XCTAssertGreaterThan(body.alpha, 250)
        XCTAssertLessThanOrEqual(abs(Int(body.red) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.green) - 21), 3)
        XCTAssertLessThanOrEqual(abs(Int(body.blue) - 23), 3)
    }

    func testChargingStatusPreservesGreenAccent() throws {
        let status = MenuBarStatus(snapshot: StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 50,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: .placeholder,
            volume: .placeholder
        ))
        let pixels = try pixels(for: status)

        XCTAssertTrue(pixels.containsColor(
            red: 52.0 / 255.0,
            green: 199.0 / 255.0,
            blue: 89.0 / 255.0,
            tolerance: 0.08,
            minimumAlpha: 0.9
        ))
    }

    func testOptionsChangeRenderedInk() throws {
        let status = MenuBarStatus.placeholder
        let withValue = try pixels(
            for: status,
            options: BatteryIconOptions(
                showsPercentage: true,
                showsChargingIndicator: true,
                usesStatusColors: true,
                criticalThreshold: 20
            )
        )
        let withoutValue = try pixels(
            for: status,
            options: BatteryIconOptions(
                showsPercentage: false,
                showsChargingIndicator: false,
                usesStatusColors: true,
                criticalThreshold: 20
            )
        )

        XCTAssertNotEqual(withValue.bytes, withoutValue.bytes)
    }

    func testRendererProducesImageForEveryPlacementPreviewState() throws {
        XCTAssertNotNil(DockIconRenderer.image(status: .placeholder))
    }

    private func pixels(
        for status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(
            status: status,
            options: options,
            connectionOptions: connectionOptions
        ))
        let representation = try XCTUnwrap(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try XCTUnwrap(representation.cgImage))
    }
}
