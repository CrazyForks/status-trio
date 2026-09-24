import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import StatusTrioCore

struct ChargingEffectRenderingTests {
    @Test func nilPhaseKeepsThePreEffectStaticPixelFingerprint() throws {
        let pixels = try renderPixels(
            snapshot: staticSnapshot,
            options: BatteryIconOptions(
                showsPercentage: false,
                showsChargingIndicator: false
            ),
            phase: nil
        )
        let fingerprint = SHA256.hash(data: Data(pixels.bytes))
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(fingerprint == "224850873cf3d786d2fe246a1b1f15c092e34297dfb944832284b2fbf671bd74")
    }

    @Test func nonChargingBatteryIgnoresSuppliedChargingPhase() throws {
        let staticPixels = try renderPixels(snapshot: staticSnapshot, phase: nil)
        let animatedPixels = try renderPixels(
            snapshot: staticSnapshot,
            phase: .init(step: 7, stepsPerCycle: 36, kind: .steady)
        )

        #expect(animatedPixels.bytes == staticPixels.bytes)
    }

    @Test func activePhaseChangesPixelsOnlyInsideTheBatteryRegion() throws {
        let snapshot = chargingSnapshot
        let staticPixels = try renderPixels(snapshot: snapshot, phase: nil)
        let animatedPixels = try renderPixels(
            snapshot: snapshot,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )
        let changedPixels = differingPixelIndices(staticPixels.bytes, animatedPixels.bytes)
        let pixelsPerSVGUnit = 20 * 2 / StatusIconGeometry.canvas.width
        let batteryBounds = StatusIconGeometry.batteryTrack(hasTopGap: false)
            .boundingBoxOfPath.insetBy(dx: -16, dy: -16)

        #expect(!changedPixels.isEmpty)
        #expect(changedPixels.allSatisfy { index in
            let x = CGFloat(index % staticPixels.width)
            let y = CGFloat(index / staticPixels.width)
            let point = CGPoint(
                x: (x + 0.5) / pixelsPerSVGUnit,
                y: (y + 0.5) / pixelsPerSVGUnit
            )
            return batteryBounds.contains(point)
        })
    }

    @Test func chargingWithoutAnIndicatorDrawsTheNoGapFullArcEffect() throws {
        let options = BatteryIconOptions(
            showsPercentage: false,
            showsChargingIndicator: false
        )
        let staticPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: nil
        )
        let phasePixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )

        #expect(phasePixels.bytes != staticPixels.bytes)
    }

    @MainActor @Test func dockRendererUsesTheSameChargingPhase() throws {
        let status = MenuBarStatus(snapshot: chargingSnapshot)
        let staticImage = try #require(DockIconRenderer.image(status: status, phase: nil))
        let phaseImage = try #require(DockIconRenderer.image(
            status: status,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        ))
        let staticCGImage = try #require(staticImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))
        let phaseCGImage = try #require(phaseImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))

        let staticPixels = try PixelBuffer(image: staticCGImage)
        let phasePixels = try PixelBuffer(image: phaseCGImage)
        #expect(phasePixels.bytes != staticPixels.bytes)
    }

    @Test func disablingTheEffectKeepsTheStaticPixels() throws {
        let options = BatteryIconOptions(showsChargingEffect: false)
        let staticPixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: nil
        )
        let phasePixels = try renderPixels(
            snapshot: chargingSnapshot,
            options: options,
            phase: .init(step: 33, stepsPerCycle: 36, kind: .steady)
        )

        #expect(phasePixels.bytes == staticPixels.bytes)
    }

    @Test func effectOptionDefaultsToEnabled() {
        #expect(BatteryIconOptions.standard.showsChargingEffect)
        #expect(BatteryIconOptions().showsChargingEffect)
    }

    private var staticSnapshot: StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 62,
                isPresent: true,
                isCharging: false,
                isLowPowerMode: false,
                isConnectedToPower: false
            ),
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil)
        )
    }

    private var chargingSnapshot: StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: 76,
                isPresent: true,
                isCharging: true,
                isLowPowerMode: false,
                isConnectedToPower: true
            ),
            wifi: WiFiStatus(state: .off, rssi: nil),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.4, isMuted: false, deviceName: nil)
        )
    }

    private func renderPixels(
        snapshot: StatusSnapshot,
        options: BatteryIconOptions = .standard,
        phase: ChargingEffectPhase?
    ) throws -> PixelBuffer {
        let image = try #require(StatusIconRenderer.render(
            snapshot: snapshot,
            size: 20,
            scale: 2,
            foreground: CGColor(gray: 1, alpha: 1),
            options: options,
            phase: phase
        ))
        return try PixelBuffer(image: image)
    }

    private func differingPixelIndices(_ lhs: [UInt8], _ rhs: [UInt8]) -> Set<Int> {
        Set(lhs.indices.compactMap { byteIndex in
            guard lhs[byteIndex] != rhs[byteIndex] else { return nil }
            return byteIndex / 4
        })
    }
}
