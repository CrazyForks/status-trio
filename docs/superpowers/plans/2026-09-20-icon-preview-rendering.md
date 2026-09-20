# Icon Preview Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop every in-app Dock-icon preview from rasterizing a full 512x512 Dock bitmap inside a SwiftUI `body`, so one icon-size slider drag costs one small render instead of ~84 MiB of allocation, while the real Dock icon stays byte-identical.

**Architecture:** Give `DockIconRenderer` an explicit square pixel length that defaults to today's 512 and keep one reusable bitmap per length; add that length to `DockIconRenderKey` so a preview raster and the Dock raster can never be confused for one another; and put a small bounded LRU (`DockIconPreviewCache`) in front of the renderer for preview tiles only. The real Dock path in `AppIconController` keeps its existing key, image cache, coalescer and 512 px / 256 pt output untouched.

**Tech Stack:** Swift 6-compatible SwiftPM package (`swift-tools-version: 6.0`), AppKit, Core Graphics, SwiftUI, Swift Testing (`import Testing`) for every new suite.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3 (`.github/workflows/release.yml:36`, `.github/workflows/release.yml:39`). The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, `weak let`, passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` resource/lproj casing.
- The app must build with the macOS 26 SDK or newer; `scripts/build-app.sh` enforces it (`scripts/build-app.sh:65-68`). Do not weaken the SDK guard or `scripts/verify-platform-version.sh`.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- A non-publishing release preflight (`gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false`) is mandatory when a change touches actor isolation, `@MainActor`, `deinit`, SwiftUI bindings, generics, or `Bundle.module` resources. Every task here edits `@MainActor` types and SwiftUI view bodies, so the preflight is required before this plan is considered done.
- Any change to menu bar icon rendering or icon settings MUST be mirrored in the Dock icon in the same change (SettingsStore option derivation, StatusBarController subscriptions, AppIconController subscriptions/state, `DockIconRenderKey` cache inputs, `DockIconRenderer` rendering, and tests covering both menu bar and Dock output). This repo treats that as a hard rule. This plan changes how previews obtain their raster, not what any surface draws, so the rule is satisfied by proving parity (Task 4) and byte-identity (Task 3) rather than by changing the menu bar path.
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`), some XCTest. Match the file you extend.

## Review Focus

- A 30 pt preview tile on a 2x display must still be crisp: the raster is the point size doubled, quantized up into 4 px buckets, never rounded down. Pinned by `DockIconPreviewMetricsTests.pixelLengthCoversEveryPreviewSizeInTheApp` and `quantizesFractionalSizesUpIntoFourPixelBuckets` in `Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift`.
- A preview that asks for an absurd point size must not allocate a giant bitmap: `pixelLength(forPointSize: 10_000)` clamps to 128 px and `DockIconRenderer.image(status:pixelLength:)` refuses anything above the Dock raster. Pinned by `DockIconPreviewMetricsTests.clampsAnAbsurdPointSize` and `DockIconRendererPixelLengthTests.rejectsANonsensicalPixelLength`.
- A user dragging the menu-bar icon-size slider across its whole 16...36 range (21 steps, each re-evaluating the Settings body) must not rasterize a Dock image per step or per tile. Pinned by `DockIconPreviewWiringTests.aSliderDragRendersThePreviewOnce`.
- A preview must never show ink the Dock icon does not show for the same state: the preview key has to carry the same `SettingsStore`-derived options and the same resolved background style as `AppIconController.renderLatestDockIcon`, differing only in raster length. Pinned by `DockIconPreviewWiringTests.thePreviewKeyCarriesTheSameIconInputsAsTheDockKey` and `DockIconPreviewCacheTests.theCachePathReproducesTheDockRasterByteForByte`.
- Revisiting the icon guide must not re-rasterize the whole state grid: 10 states x 2 appearances render at most once each and a second visit renders nothing. Pinned by `DockIconPreviewGuideTests.revisitingTheGuideRendersNothingNew`.

---

### Task 1: Render The Dock Artwork At A Requested Pixel Length

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift` (lines 24-175: `DockIconRenderer`, `image(status:...)`, `scratchContext()`)
- Test: `Tests/StatusTrioCoreTests/DockIconRendererPixelLengthTests.swift` (create)

**Interfaces:**
- Produces: `DockIconRenderer.image(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:pixelLength:) -> NSImage?` (`pixelLength` last, defaulted).
- Produces: `DockIconRenderer.scale: CGFloat` (2).
- Keeps: `DockIconRenderer.pixelSize` (512), `DockIconRenderer.logicalSize` (256), `DockIconRenderer.image(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` — every existing call site keeps compiling unchanged.
- Consumes: nothing.

- [ ] **Step 1: Write the failing renderer tests**

Create `Tests/StatusTrioCoreTests/DockIconRendererPixelLengthTests.swift`:

```swift
import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRendererPixelLengthTests {
    @Test func keepsTheDockRasterByDefault() throws {
        let image = try #require(DockIconRenderer.image(status: .placeholder))
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )

        #expect(DockIconRenderer.pixelSize == 512)
        #expect(DockIconRenderer.scale == 2)
        #expect(representation.pixelsWide == DockIconRenderer.pixelSize)
        #expect(representation.pixelsHigh == DockIconRenderer.pixelSize)
        #expect(image.size == NSSize(width: 256, height: 256))
        #expect(
            DockIconRenderer.logicalSize
                == CGFloat(DockIconRenderer.pixelSize) / DockIconRenderer.scale
        )
    }

    @Test func rendersAPreviewAtTheRequestedPixelLength() throws {
        let image = try #require(
            DockIconRenderer.image(status: .placeholder, pixelLength: 112)
        )
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )

        #expect(representation.pixelsWide == 112)
        #expect(representation.pixelsHigh == 112)
        #expect(image.size == NSSize(width: 56, height: 56))
    }

    /// The Dock raster is the acceptance surface for every Dock-icon test in the
    /// repo, so asking for it explicitly must not move a single pixel.
    @Test func explicitDockPixelLengthMatchesTheDefaultRaster() throws {
        let legacy = try #require(DockIconRenderer.image(status: .placeholder))
        let explicit = try #require(
            DockIconRenderer.image(
                status: .placeholder,
                pixelLength: DockIconRenderer.pixelSize
            )
        )
        let legacyPixels = try pixels(of: legacy)
        let explicitPixels = try pixels(of: explicit)

        #expect(legacyPixels.bytes == explicitPixels.bytes)
    }

    @Test func aPreviewRasterKeepsTheSameArtwork() throws {
        let preview = try pixels(
            of: try #require(
                DockIconRenderer.image(status: .placeholder, pixelLength: 128)
            )
        )
        let body = preview.rgba(
            x: preview.width * 12 / 100,
            y: preview.height / 2
        )

        #expect(preview.width == 128)
        #expect(body.alpha > 250)
        #expect(abs(Int(body.red) - 21) <= 3)
        #expect(abs(Int(body.green) - 21) <= 3)
        #expect(abs(Int(body.blue) - 23) <= 3)
    }

    @Test func reusesTheBufferAcrossLengths() throws {
        // Two lengths in a row must not leave drawing state behind: the second
        // render has to be byte-identical to the same render performed first.
        let firstPass = try pixels(
            of: try #require(
                DockIconRenderer.image(status: .placeholder, pixelLength: 64)
            )
        )
        _ = try #require(
            DockIconRenderer.image(status: .placeholder, pixelLength: 512)
        )
        let secondPass = try pixels(
            of: try #require(
                DockIconRenderer.image(status: .placeholder, pixelLength: 64)
            )
        )

        #expect(firstPass.bytes == secondPass.bytes)
    }

    @Test func rejectsANonsensicalPixelLength() {
        #expect(DockIconRenderer.image(status: .placeholder, pixelLength: 0) == nil)
        #expect(DockIconRenderer.image(status: .placeholder, pixelLength: -8) == nil)
        #expect(DockIconRenderer.image(status: .placeholder, pixelLength: 4096) == nil)
    }

    private func pixels(of image: NSImage) throws -> PixelBuffer {
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter DockIconRendererPixelLengthTests`

Expected: compile failure — `extra argument 'pixelLength' in call` and `type 'DockIconRenderer' has no member 'scale'`. The test target does not build, so no test runs.

- [ ] **Step 3: Add the pixel length and per-length scratch buffers**

In `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`, replace lines 26-27 with:

```swift
    /// The real Dock icon is a 512 px bitmap presented as a 256 pt 2x asset.
    static let scale: CGFloat = 2
    static let logicalSize: CGFloat = 256
    static let pixelSize = 512
```

Replace the signature through the canvas clear (lines 82-100) with:

```swift
    /// Renders the Dock artwork at `pixelLength` square pixels.
    ///
    /// `pixelLength` defaults to the real Dock raster, so the Dock path keeps its
    /// output. Preview tiles pass the pixel length their on-screen size actually
    /// needs, which is what stops a 30 pt tile from allocating 1 MiB.
    static func image(
        status: MenuBarStatus,
        options: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle = .dark,
        pixelLength: Int = DockIconRenderer.pixelSize
    ) -> NSImage? {
        guard pixelLength > 0, pixelLength <= pixelSize else { return nil }

        let palette = palette(for: backgroundStyle)

        let canvasLength = CGFloat(pixelLength)
        guard let context = scratchContext(pixelLength: pixelLength) else { return nil }

        context.saveGState()
        defer { context.restoreGState() }
        context.clear(CGRect(x: 0, y: 0, width: canvasLength, height: canvasLength))
```

The old "Reuse one bitmap buffer across renders" comment (lines 95-97) moves to `scratchContext` in the next edit, because the reuse is now per pixel length. Everything from `context.scaleBy(` (line 102) down to the glyph `draw` call stays exactly as it is.

Replace the tail of `image` (lines 139-147) with:

```swift
        guard let output = context.makeImage() else { return nil }

        let logicalLength = CGFloat(pixelLength) / Self.scale
        let representation = NSBitmapImageRep(cgImage: output)
        representation.size = NSSize(width: logicalLength, height: logicalLength)

        let image = NSImage(size: NSSize(width: logicalLength, height: logicalLength))
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }
```

Replace `reusedContext` / `scratchContext()` (lines 150-165) with:

```swift
    /// One reusable bitmap per pixel length: the Dock icon is redrawn on every
    /// status change and a preview tile is redrawn whenever its pane
    /// re-evaluates, so allocating a fresh buffer each time leaves the freed
    /// pages in the process.
    private static var reusedContexts: [Int: CGContext] = [:]
    private static var reusedContextOrder: [Int] = []
    /// The 512 px Dock raster plus the handful of preview lengths the Settings
    /// pane and the icon guide use.
    private static let maximumReusedContexts = 6

    private static func scratchContext(pixelLength: Int) -> CGContext? {
        if let reused = reusedContexts[pixelLength] {
            touchScratchContext(pixelLength)
            return reused
        }

        guard let context = CGContext(
            data: nil,
            width: pixelLength,
            height: pixelLength,
            bitsPerComponent: 8,
            bytesPerRow: pixelLength * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        reusedContexts[pixelLength] = context
        touchScratchContext(pixelLength)

        while reusedContextOrder.count > maximumReusedContexts {
            let oldest = reusedContextOrder.removeFirst()
            reusedContexts[oldest] = nil
        }
        return context
    }

    private static func touchScratchContext(_ pixelLength: Int) {
        reusedContextOrder.removeAll { $0 == pixelLength }
        reusedContextOrder.append(pixelLength)
    }
```

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter DockIconRendererPixelLengthTests`

Expected: PASS (6 tests).

- [ ] **Step 5: Run the existing Dock renderer tests**

Run: `swift test --filter DockIconRendererTests`

Expected: PASS — the raster size, body colour, margin and glyph assertions are unchanged.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift \
        Tests/StatusTrioCoreTests/DockIconRendererPixelLengthTests.swift
git commit -m "perf(icon): render Dock artwork at a requested pixel length"
```

---

### Task 2: Make The Raster Length Part Of The Render Key

**Files:**
- Modify: `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` (lines 4-63: `DockIconRenderKey`)
- Test: `Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift` (create, suite `DockIconRenderKeyPixelLengthTests`)

**Interfaces:**
- Produces: `DockIconRenderKey.pixelLength: Int`.
- Produces: `DockIconRenderKey.init(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:pixelLength:)` with `pixelLength` defaulting to `DockIconRenderer.pixelSize`.
- Keeps: every existing key construction and `DockIconRenderCache.shouldRender(_:)` / `DockIconImageCache` behaviour for Dock-path keys.
- Consumes: `DockIconRenderer.pixelSize` from Task 1.

- [ ] **Step 1: Write the failing key tests**

Create `Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift`:

```swift
import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRenderKeyPixelLengthTests {
    @Test func defaultsToTheDockRasterLength() {
        let key = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )

        #expect(key.pixelLength == DockIconRenderer.pixelSize)
    }

    @Test func distinguishesTheSameStateAtAPreviewLength() {
        let dock = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let preview = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark,
            pixelLength: 112
        )

        #expect(dock != preview)
        #expect(preview.pixelLength == 112)
    }

    /// The Dock path's "render only when the key changed" behaviour must not
    /// change for keys it builds itself.
    @Test func keepsTheDockDeduplicationBehaviour() {
        var cache = DockIconRenderCache()
        let dock = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark
        )
        let preview = DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark,
            pixelLength: 112
        )

        #expect(cache.shouldRender(dock))
        #expect(cache.shouldRender(dock) == false)
        #expect(cache.shouldRender(preview))
        #expect(cache.shouldRender(preview) == false)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter DockIconRenderKeyPixelLengthTests`

Expected: compile failure — `extra argument 'pixelLength' in call` and `value of type 'DockIconRenderKey' has no member 'pixelLength'`.

- [ ] **Step 3: Add the length to the key**

In `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift`, replace the doc comment and struct tail (lines 1-3 and 18-27) so the key reads:

```swift
/// Identifies what a Dock-icon raster actually contains, so signal noise that
/// cannot change a pixel (a different RSSI inside the same bar count, a
/// different volume inside the same dot count) does not trigger another render.
///
/// The raster's pixel length is part of the identity: the Dock icon and a
/// preview tile of the same state are different bitmaps, and serving one for the
/// other would either blur the Dock or waste a megabyte on a 30 pt tile.
struct DockIconRenderKey: Equatable, Hashable {
```

and

```swift
    let backgroundStyle: DockIconBackgroundStyle
    let pixelLength: Int

    init(
        status: MenuBarStatus,
        options: BatteryIconOptions,
        connectionOptions: ConnectionIconOptions,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        backgroundStyle: DockIconBackgroundStyle,
        pixelLength: Int = DockIconRenderer.pixelSize
    ) {
```

Then add `self.pixelLength = pixelLength` after `self.backgroundStyle = backgroundStyle` (line 56).

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter DockIconRenderKeyPixelLengthTests`

Expected: PASS (3 tests).

- [ ] **Step 5: Run the existing cache suite unchanged**

Run: `swift test --filter DockIconRenderCacheTests`

Expected: PASS — `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift` is owned by the parity/lifecycle plan and must not be edited here; it passes because the new parameter is defaulted.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift \
        Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift
git commit -m "perf(icon): key Dock rasters by pixel length"
```

---

### Task 3: Add Preview Metrics And A Bounded Preview Cache

**Files:**
- Create: `Sources/StatusTrioCore/UI/Icon/DockIconPreviewCache.swift` (`DockIconPreviewMetrics`, `DockIconPreviewCache`)
- Test: `Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift` (append suites `DockIconPreviewMetricsTests`, `DockIconPreviewCacheTests`)

**Interfaces:**
- Produces: `DockIconPreviewMetrics.deviceScale: CGFloat`, `DockIconPreviewMetrics.maximumPixelLength: Int`, `DockIconPreviewMetrics.pixelLength(forPointSize:) -> Int`.
- Produces: `DockIconPreviewCache.shared: DockIconPreviewCache`, `DockIconPreviewCache.defaultLimit: Int`, `init(limit:)`, `renderCount: Int`, `renderedPixelLengths: [Int]`, `image(for:render:) -> NSImage?`, `reset()`.
- Consumes: `DockIconRenderer.image(status:...:pixelLength:)` (Task 1), `DockIconRenderKey.pixelLength` (Task 2), the existing `DockIconImageCache`.

- [ ] **Step 1: Write the failing metrics and cache tests**

Append to `Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift`:

```swift
@MainActor
struct DockIconPreviewMetricsTests {
    /// The sizes the app actually asks for: 30 pt for the Dock background
    /// preview tiles (`Sources/StatusTrioCore/UI/Settings/SettingsVisualPreviews.swift:189-228`),
    /// 44 pt for the `DockIconTile` default, 56 pt in the icon guide grid
    /// (`Sources/StatusTrioCore/UI/IconGuideView.swift:550`).
    @Test func pixelLengthCoversEveryPreviewSizeInTheApp() {
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 30) == 60)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 44) == 88)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 56) == 112)
    }

    @Test func quantizesFractionalSizesUpIntoFourPixelBuckets() {
        let lengths = [30.0, 30.2, 30.6, 30.9, 31.0].map {
            DockIconPreviewMetrics.pixelLength(forPointSize: $0)
        }

        #expect(lengths == [60, 64, 64, 64, 64])
    }

    @Test func clampsAnAbsurdPointSize() {
        #expect(DockIconPreviewMetrics.maximumPixelLength == 128)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 0) == 4)
        #expect(DockIconPreviewMetrics.pixelLength(forPointSize: 10_000) == 128)
        #expect(
            DockIconPreviewMetrics.pixelLength(forPointSize: 10_000)
                < DockIconRenderer.pixelSize
        )
    }
}

@MainActor
struct DockIconPreviewCacheTests {
    @Test func reusesOneRasterForARepeatedKey() {
        let cache = DockIconPreviewCache(limit: 4)
        let key = previewKey(pixelLength: 112)
        var renders = 0

        let first = cache.image(for: key) {
            renders += 1
            return NSImage(size: NSSize(width: 56, height: 56))
        }
        let second = cache.image(for: key) {
            renders += 1
            return NSImage(size: NSSize(width: 56, height: 56))
        }

        #expect(renders == 1)
        #expect(cache.renderCount == 1)
        #expect(cache.renderedPixelLengths == [112])
        #expect(first === second)
    }

    @Test func rendersAgainWhenOnlyThePixelLengthChanges() {
        let cache = DockIconPreviewCache(limit: 4)
        var renders = 0

        for pixelLength in [112, 60] {
            _ = cache.image(for: previewKey(pixelLength: pixelLength)) {
                renders += 1
                return NSImage(size: NSSize(width: 8, height: 8))
            }
        }

        #expect(renders == 2)
        #expect(cache.renderedPixelLengths == [112, 60])
    }

    @Test func evictsTheOldestRasterWhenFull() {
        let cache = DockIconPreviewCache(limit: 2)
        var renders = 0

        for pixelLength in [60, 88, 112, 60] {
            _ = cache.image(for: previewKey(pixelLength: pixelLength)) {
                renders += 1
                return NSImage(size: NSSize(width: 8, height: 8))
            }
        }

        #expect(renders == 4, "The first raster must have been evicted before it was asked for again.")
    }

    @Test func resetDropsEveryRaster() {
        let cache = DockIconPreviewCache(limit: 2)
        let key = previewKey(pixelLength: 60)

        _ = cache.image(for: key) {
            NSImage(size: NSSize(width: 8, height: 8))
        }
        cache.reset()
        _ = cache.image(for: key) {
            NSImage(size: NSSize(width: 8, height: 8))
        }

        #expect(cache.renderCount == 2, "The raster must be rendered again after reset.")
    }

    @Test func aFailedRenderIsCountedButNotCached() {
        let cache = DockIconPreviewCache(limit: 2)

        let image = cache.image(for: previewKey(pixelLength: 60)) { nil as NSImage? }

        #expect(image == nil)
        #expect(cache.renderCount == 1)
        #expect(cache.renderedPixelLengths == [60])
    }

    /// The preview path at the Dock raster length must be the Dock icon, byte for
    /// byte. This is the "before/after" guard for Task 1's refactor: the legacy
    /// call shape and the preview call shape have to agree pixel for pixel.
    @Test func theCachePathReproducesTheDockRasterByteForByte() throws {
        let cache = DockIconPreviewCache(limit: 2)
        let status = MenuBarStatus.placeholder
        let key = previewKey(
            pixelLength: DockIconRenderer.pixelSize
        )
        let dock = try #require(DockIconRenderer.image(status: status))
        let throughTheCache = try #require(
            cache.image(for: key) {
                DockIconRenderer.image(
                    status: status,
                    pixelLength: DockIconRenderer.pixelSize
                )
            }
        )
        let dockPixels = try pixels(of: dock)
        let cachedPixels = try pixels(of: throughTheCache)

        #expect(dockPixels.bytes == cachedPixels.bytes)
    }

    private func previewKey(pixelLength: Int) -> DockIconRenderKey {
        DockIconRenderKey(
            status: .placeholder,
            options: .standard,
            connectionOptions: .standard,
            backgroundStyle: .dark,
            pixelLength: pixelLength
        )
    }

    private func pixels(of image: NSImage) throws -> PixelBuffer {
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter DockIconPreviewMetricsTests`
Run: `swift test --filter DockIconPreviewCacheTests`

Expected: compile failure — `cannot find 'DockIconPreviewMetrics' in scope` and `cannot find 'DockIconPreviewCache' in scope`.

- [ ] **Step 3: Create `DockIconPreviewCache.swift`**

Create `Sources/StatusTrioCore/UI/Icon/DockIconPreviewCache.swift`:

```swift
import AppKit

/// Maps an on-screen preview size to the pixel length its raster needs.
///
/// Preview tiles are drawn at 30-56 pt, so at 2x they need 60-112 px. The Dock's
/// 512 px raster is ~1 MiB, and rendering it for a 30 pt tile is the allocation
/// this type exists to prevent. Sizes are quantized up into 4 px buckets so a
/// fractional layout size cannot churn the cache with a new raster per frame.
enum DockIconPreviewMetrics {
    static let deviceScale: CGFloat = 2
    /// A preview never needs more than this; it also keeps a runaway call site
    /// from reaching the Dock raster length by accident.
    static let maximumPixelLength = 128
    private static let bucket = 4

    static func pixelLength(forPointSize pointSize: CGFloat) -> Int {
        let requested = (max(1, pointSize) * deviceScale).rounded(.up)
        let clamped = min(requested, CGFloat(maximumPixelLength))
        return Int((clamped / CGFloat(bucket)).rounded(.up)) * bucket
    }
}

/// Keeps the rasters that in-app previews draw, so re-evaluating a SwiftUI body
/// costs a dictionary lookup instead of a full Core Graphics render.
///
/// Storage is the same `DockIconImageCache` the real Dock path uses, keyed by
/// `DockIconRenderKey` — which now carries the pixel length, so a preview can
/// never be served the Dock's bitmap.
@MainActor
final class DockIconPreviewCache {
    static let shared = DockIconPreviewCache()
    static let defaultLimit = 32

    private let images: DockIconImageCache
    /// Renderer invocations, including one that returned nil. Tests read this to
    /// prove a body evaluation did not rasterize.
    private(set) var renderCount = 0
    private(set) var renderedPixelLengths: [Int] = []

    init(limit: Int = DockIconPreviewCache.defaultLimit) {
        images = DockIconImageCache(limit: limit)
    }

    func image(for key: DockIconRenderKey, render: () -> NSImage?) -> NSImage? {
        if let cached = images.image(for: key) { return cached }

        renderCount += 1
        renderedPixelLengths.append(key.pixelLength)

        guard let image = render() else { return nil }
        images.store(image, for: key)
        return image
    }

    func reset() {
        images.reset()
    }
}
```

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter DockIconPreviewMetricsTests`
Run: `swift test --filter DockIconPreviewCacheTests`

Expected: PASS (3 + 6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/StatusTrioCore/UI/Icon/DockIconPreviewCache.swift \
        Tests/StatusTrioCoreTests/DockIconPreviewCacheTests.swift
git commit -m "perf(icon): add a size-aware cache for preview rasters"
```

---

### Task 4: Route The Preview Tiles Through The Cache

**Files:**
- Modify: `Sources/StatusTrioCore/UI/IconPreviewComponents.swift` (lines 282-329: `DockIconTile`)
- Modify: `Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift` (lines 65-100: `DockIconPreviewTile`)
- Test: `Tests/StatusTrioCoreTests/DockIconPreviewWiringTests.swift` (create)

**Interfaces:**
- Produces: `DockIconTile.previewCache: DockIconPreviewCache?` (defaulted `nil`), `DockIconTile.pixelLength: Int`, `DockIconTile.renderKey: DockIconRenderKey`, `DockIconTile.previewImage: NSImage?`.
- Produces: `DockIconPreviewTile.previewCache: DockIconPreviewCache?` (defaulted `nil`), `DockIconPreviewTile.renderKey: DockIconRenderKey`, `DockIconPreviewTile.previewImage: NSImage?`.
- Consumes: `DockIconPreviewCache` and `DockIconPreviewMetrics` (Task 3), `DockIconRenderKey.pixelLength` (Task 2).
- Keeps: `DockIconTile(status:batteryOptions:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:size:highlightedPart:highlightOpacity:)` — the new parameter is appended, so `DockPreviewBar` (`Sources/StatusTrioCore/UI/IconPreviewComponents.swift:193-202`), `IconGuideStateCard` (`Sources/StatusTrioCore/UI/IconGuideView.swift:533-551`), the Dock background group (`Sources/StatusTrioCore/UI/Settings/SettingsVisualPreviews.swift:189-228`) and `StatusIconPreviewCardTests` keep compiling and keep their layout.

- [ ] **Step 1: Write the failing wiring tests**

Create `Tests/StatusTrioCoreTests/DockIconPreviewWiringTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconPreviewWiringTests {
    @Test func evaluatingTheTileBodyTwiceRendersOnce() {
        let cache = DockIconPreviewCache(limit: 4)
        let tile = DockIconTile(
            status: .placeholder,
            backgroundStyle: .dark,
            size: 56,
            previewCache: cache
        )

        _ = tile.body
        _ = tile.body

        #expect(cache.renderCount == 1)
        #expect(cache.renderedPixelLengths == [112])
        #expect(tile.pixelLength == 112)
    }

    /// The icon-size slider writes `store.iconSize` once per step
    /// (`Sources/StatusTrioCore/UI/Settings/AppIconSectionView.swift:106-112`)
    /// and `SettingsView` observes the store
    /// (`Sources/StatusTrioCore/UI/Settings/SettingsView.swift:6`), so one drag
    /// re-evaluates the whole pane ~21 times. The Dock tile does not depend on
    /// the menu bar icon size, so it must render once.
    @Test func aSliderDragRendersThePreviewOnce() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        let cache = DockIconPreviewCache(limit: 4)
        let tile = DockIconPreviewTile(
            store: harness.settings,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: cache
        )
        var images: [NSImage] = []

        for size in stride(
            from: SettingsStore.iconSizeRange.lowerBound,
            through: SettingsStore.iconSizeRange.upperBound,
            by: 1
        ) {
            harness.settings.iconSize = size
            images.append(try #require(tile.previewImage))
        }

        #expect(images.count == 21)
        #expect(cache.renderCount == 1)
        #expect(cache.renderedPixelLengths == [60])
        #expect(images.allSatisfy { $0 === images[0] })
    }

    @Test func theTileStillLaysOutAtItsRequestedSize() {
        let tile = DockIconTile(
            status: .placeholder,
            backgroundStyle: .dark,
            size: 56,
            previewCache: DockIconPreviewCache(limit: 2)
        )
        let hostingView = NSHostingView(rootView: tile)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        #expect(abs(size.width - 56) <= 0.5)
        #expect(abs(size.height - 56) <= 0.5)
    }

    /// `AppIconController.renderLatestDockIcon` builds the Dock key from
    /// `StatusIconAppearance(settings:)` and `DockIconBackgroundResolver`
    /// (`Sources/StatusTrioCore/App/AppIconController.swift:216-229`). The only
    /// intentional difference between that key and a preview's key is the raster
    /// length, so everything else has to match.
    @Test func thePreviewKeyCarriesTheSameIconInputsAsTheDockKey() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        let store = harness.settings
        store.dockIconBackgroundPreference = .light
        store.volumeDisplayStyle = .arc
        store.ringStrokeStyle = .bold
        store.showsBatteryPercentage = false
        store.usesBatteryStatusColors = false
        store.replacesNetworkIconWithBluetoothAudio = true

        let status = MenuBarStatus(snapshot: harness.statusStore.snapshot)
        let appearance = StatusIconAppearance(settings: store)
        let backgroundStyle = DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: .default,
            isDarkAppearance: false
        )
        let previewLength = DockIconPreviewMetrics.pixelLength(forPointSize: 30)
        let dockKey = DockIconRenderKey(
            status: status,
            options: appearance.batteryOptions,
            connectionOptions: appearance.connectionOptions,
            volumeOptions: appearance.volumeOptions,
            bluetoothAudioOptions: appearance.bluetoothAudioOptions,
            backgroundStyle: backgroundStyle
        )
        let dockKeyAtPreviewLength = DockIconRenderKey(
            status: status,
            options: appearance.batteryOptions,
            connectionOptions: appearance.connectionOptions,
            volumeOptions: appearance.volumeOptions,
            bluetoothAudioOptions: appearance.bluetoothAudioOptions,
            backgroundStyle: backgroundStyle,
            pixelLength: previewLength
        )
        let previewKey = DockIconPreviewTile(
            store: store,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: DockIconPreviewCache(limit: 4)
        ).renderKey

        #expect(backgroundStyle == .light)
        #expect(dockKey.pixelLength == DockIconRenderer.pixelSize)
        #expect(previewKey == dockKeyAtPreviewLength)
    }

    /// Mirrors `AppIconControllerTests.menuBarIconSizeDoesNotChangeTheDockIcon`:
    /// the size slider is menu-bar only, so it must not create a new Dock raster.
    @Test func iconSizeDoesNotChangeThePreviewKey() throws {
        let harness = try PreviewWiringHarness()
        defer { harness.cleanUp() }
        let tile = DockIconPreviewTile(
            store: harness.settings,
            statusStore: harness.statusStore,
            size: 30,
            previewCache: DockIconPreviewCache(limit: 4)
        )
        let before = tile.renderKey

        harness.settings.iconSize = SettingsStore.iconSizeRange.upperBound

        #expect(tile.renderKey == before)
    }
}

@MainActor
private struct PreviewWiringHarness {
    let suiteName: String
    let defaults: UserDefaults
    let settings: SettingsStore
    let statusStore: SystemStatusStore

    init() throws {
        let name = "StatusTrioCoreTests.DockIconPreviewWiring.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw PreviewWiringError.missingDefaultsSuite
        }
        defaults.removeTestSuite(named: name)
        suiteName = name
        self.defaults = defaults
        settings = SettingsStore(defaults: defaults)
        statusStore = SystemStatusStore(
            batteryMonitor: PreviewBatteryMonitor(),
            wifiMonitor: PreviewWiFiMonitor(),
            volumeMonitor: PreviewVolumeMonitor()
        )
    }

    func cleanUp() {
        defaults.removeTestSuite(named: suiteName)
    }
}

private enum PreviewWiringError: Error {
    case missingDefaultsSuite
}

@MainActor
private final class PreviewBatteryMonitor: BatteryMonitoring {
    let updates = AsyncStream<BatteryStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class PreviewWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() {}
}

@MainActor
private final class PreviewVolumeMonitor: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter DockIconPreviewWiringTests`

Expected: compile failure — `extra argument 'previewCache' in call` and `value of type 'DockIconTile' has no member 'previewImage'` (`renderKey`, `pixelLength` likewise).

- [ ] **Step 3: Wire `DockIconTile` to the cache**

In `Sources/StatusTrioCore/UI/IconPreviewComponents.swift`, replace `DockIconTile` (lines 283-329) with:

```swift
struct DockIconTile: View {
    let status: MenuBarStatus
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    var backgroundStyle: DockIconBackgroundStyle = .dark
    var size: CGFloat = 44
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1
    /// Injected by tests; the app shares one bounded cache.
    var previewCache: DockIconPreviewCache? = nil

    /// The raster length this tile's on-screen size needs, never the Dock's.
    var pixelLength: Int {
        DockIconPreviewMetrics.pixelLength(forPointSize: size)
    }

    /// What the tile draws, identified exactly like the Dock path identifies its
    /// own rasters. A body evaluation only looks this up.
    @MainActor
    var renderKey: DockIconRenderKey {
        DockIconRenderKey(
            status: status,
            options: batteryOptions,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            backgroundStyle: backgroundStyle,
            pixelLength: pixelLength
        )
    }

    /// The single place this tile resolves its bitmap.
    @MainActor
    var previewImage: NSImage? {
        let cache = previewCache ?? DockIconPreviewCache.shared
        return cache.image(for: renderKey) {
            DockIconRenderer.image(
                status: status,
                options: batteryOptions,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: bluetoothAudioOptions,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength
            )
        }
    }

    var body: some View {
        ZStack {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            }

            if let highlightedPart {
                let glyphFrame = DockIconGlyphLayout.frame(
                    in: CGRect(x: 0, y: 0, width: size, height: size)
                )
                StatusIconPartHighlight(
                    part: highlightedPart,
                    volumeDisplayStyle: volumeOptions.displayStyle,
                    lineWidth: max(3, size * 0.07)
                )
                .frame(width: glyphFrame.width, height: glyphFrame.height)
                .position(x: glyphFrame.midX, y: glyphFrame.midY)
                .opacity(highlightOpacity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Wire `DockIconPreviewTile` to the same cache**

In `Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift`, replace `DockIconPreviewTile` (lines 66-100) with:

```swift
struct DockIconPreviewTile: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var size: CGFloat = 44
    var overrideStyle: DockIconBackgroundStyle? = nil
    var previewCache: DockIconPreviewCache? = nil

    var body: some View {
        tile
            .animation(.easeInOut(duration: 0.15), value: store.batteryIconOptions)
            .animation(.easeInOut(duration: 0.15), value: store.connectionIconOptions)
            .animation(.easeInOut(duration: 0.15), value: store.volumeIconOptions)
            .animation(.easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
            .accessibilityHidden(true)
    }

    @MainActor
    var renderKey: DockIconRenderKey { tile.renderKey }

    @MainActor
    var previewImage: NSImage? { tile.previewImage }

    /// The tile the body renders, so a test reads exactly the key the body uses.
    private var tile: DockIconTile {
        DockIconTile(
            status: MenuBarStatus(snapshot: statusStore.snapshot),
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            backgroundStyle: resolvedBackgroundStyle,
            size: size,
            previewCache: previewCache
        )
    }

    private var resolvedBackgroundStyle: DockIconBackgroundStyle {
        if let overrideStyle {
            return overrideStyle
        }
        return DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }
}
```

- [ ] **Step 5: Run the wiring tests**

Run: `swift test --filter DockIconPreviewWiringTests`

Expected: PASS (5 tests).

- [ ] **Step 6: Run the preview surface tests and the Dock controller tests**

Run: `swift test --filter StatusIconPreviewCardTests`
Run: `swift test --filter AppIconControllerTests`
Run: `swift test --filter Issue13IconParityTests`

Expected: PASS — the menu bar simulation bar, the real Dock path and the icon-parity suite are untouched.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/UI/IconPreviewComponents.swift \
        Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift \
        Tests/StatusTrioCoreTests/DockIconPreviewWiringTests.swift
git commit -m "perf(icon): serve preview tiles from the size-aware cache"
```

---

### Task 5: Stop The Icon Guide Re-Rasterizing Its Whole Grid

**Files:**
- Modify: `Sources/StatusTrioCore/UI/IconGuideView.swift` (lines 533-580: `IconGuideStateCard`)
- Test: `Tests/StatusTrioCoreTests/DockIconPreviewGuideTests.swift` (create)

**Interfaces:**
- Produces: `IconGuideStateCard` becomes internal (was `private`), its `@EnvironmentObject var localization` becomes non-private and it gains `previewCache: DockIconPreviewCache?` (defaulted `nil`) — a `private` stored property would keep the memberwise initializer `private` and make the card unreachable from the test target.
- Keeps: `IconGuideStateGalleryView` (lines 474-531) unchanged; it keeps constructing the card with `(state:settings:previewAppearance:)` at lines 521-526, and the card's `nil` cache falls back to `DockIconPreviewCache.shared`.
- Consumes: `DockIconTile.previewCache` (Task 4), `DockIconPreviewCache`/`DockIconPreviewMetrics` (Task 3).

- [ ] **Step 1: Write the failing guide tests**

Create `Tests/StatusTrioCoreTests/DockIconPreviewGuideTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconPreviewGuideTests {
    /// The guide shows 10 states (`IconGuideState.all`) at 56 pt
    /// (`Sources/StatusTrioCore/UI/IconGuideView.swift:541-550`) and the
    /// appearance picker re-renders all of them. Each card may rasterize at most
    /// once per (state, appearance), and revisiting the guide must rasterize
    /// nothing: before this task every hosting pass rendered all 20 again.
    @Test func revisitingTheGuideRendersNothingNew() throws {
        let suiteName = "StatusTrioCoreTests.DockIconPreviewGuide.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { TestUserDefaults.removeSuite(named: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        let localization = Localization(
            defaults: defaults,
            preferredLanguages: [AppLanguage.english.rawValue]
        )
        let cache = DockIconPreviewCache(limit: 64)
        let cardCount = IconGuideState.all.count
            * IconGuidePreviewAppearance.allCases.count
        var firstPassCount = 0

        for pass in 0..<2 {
            for appearance in IconGuidePreviewAppearance.allCases {
                for state in IconGuideState.all {
                    let card = IconGuideStateCard(
                        state: state,
                        settings: settings,
                        previewAppearance: appearance,
                        previewCache: cache
                    )
                    .environmentObject(localization)
                    let hostingView = NSHostingView(rootView: card)
                    hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
                    hostingView.layoutSubtreeIfNeeded()
                    _ = hostingView.fittingSize
                }
            }

            if pass == 0 {
                firstPassCount = cache.renderCount
            }
        }

        #expect(cardCount == 20)
        #expect(firstPassCount >= 1)
        #expect(firstPassCount <= cardCount)
        #expect(
            cache.renderCount == firstPassCount,
            "The second visit to the guide must reuse every raster."
        )
        #expect(cache.renderedPixelLengths.allSatisfy { $0 == 112 })
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `swift test --filter DockIconPreviewGuideTests`

Expected: compile failure — `extra argument 'previewCache' in call`, and `'IconGuideStateCard' is inaccessible due to 'private' protection level`.

- [ ] **Step 3: Make the card injectable**

In `Sources/StatusTrioCore/UI/IconGuideView.swift`, change the card declaration (lines 533-541) to:

```swift
/// One state card in the guide grid. Internal, and with an internal memberwise
/// initializer, so a test can host the exact view the grid builds: a `private`
/// stored property anywhere in the card would make that initializer `private`
/// and leave the guide's render behaviour untestable.
struct IconGuideStateCard: View {
    let state: IconGuideState
    @ObservedObject var settings: SettingsStore
    let previewAppearance: IconGuidePreviewAppearance
    var previewCache: DockIconPreviewCache? = nil
    @EnvironmentObject var localization: Localization

    var body: some View {
        VStack(spacing: 10) {
            DockIconTile(
                status: state.status,
                batteryOptions: settings.batteryIconOptions,
                connectionOptions: settings.connectionIconOptions,
                volumeOptions: volumeOptions,
                bluetoothAudioOptions: state.bluetoothAudioOptions(
                    configuring: settings.bluetoothAudioIconOptions
                ),
                backgroundStyle: previewAppearance.dockBackgroundStyle,
                size: 56,
                previewCache: previewCache
            )
```

Leave the rest of `body` (the title text and the card chrome, lines 552-580) unchanged, and leave `IconGuideStateGalleryView` unchanged.

- [ ] **Step 4: Run the guide tests**

Run: `swift test --filter DockIconPreviewGuideTests`

Expected: PASS (1 test). If `firstPassCount` is 0, the hosting view did not evaluate the card body: attach it to a window the way `Tests/StatusTrioCoreTests/SettingsPagePinningTests.swift:197-213` does (`window.contentView = hostingView`, then `window.displayIfNeeded()`), which forces a real display pass.

- [ ] **Step 5: Run the existing guide suites**

Run: `swift test --filter IconGuideTests`
Run: `swift test --filter IconGuideRedesignTests`

Expected: PASS — the cards still render, still at 56 pt, with the same artwork assertions.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/UI/IconGuideView.swift \
        Tests/StatusTrioCoreTests/DockIconPreviewGuideTests.swift
git commit -m "perf(icon): cache the icon guide's Dock previews"
```

---

### Task 6: Full Verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full test suite**

Run: `swift test`

Expected: every test passes, including the four new suites and every pre-existing Dock/menu bar suite.

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`

Expected: successful build against the local SDK.

- [ ] **Step 3: Measure the preview path after the change**

Run the app, open Settings > App Icon, and sample the process while dragging the icon-size slider across its whole range:

```bash
sample "$(pgrep -x StatusTrio)" 5 -file /tmp/status-trio-preview-after.txt
grep -c "DockIconRenderer.image" /tmp/status-trio-preview-after.txt
```

Expected: the Dock rasterizer appears at most once per tile (the first paint of a new state), not once per slider step. The review baseline for this drag was ~84 full renders. The deterministic evidence is `DockIconPreviewWiringTests.aSliderDragRendersThePreviewOnce` (21 body re-evaluations, 1 render); record the sample count in the commit message or PR body.

- [ ] **Step 4: Run the non-publishing release preflight**

Run:

```bash
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref "$BRANCH" \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

RUN_ID="$(gh run list --repo lingyired/status-trio --workflow release.yml \
  --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID" --repo lingyired/status-trio --exit-status
```

Expected: workflow passes without publishing. This plan edits `@MainActor` types and SwiftUI view bodies, so the preflight is not optional.

- [ ] **Step 5: Review the diff**

Run: `git diff --check` and `git status --short`

Expected: no whitespace errors; only the ten files listed in the tasks are modified or created (six production files, four new test files).

## Verification

- `swift test` (full suite) and `swift build -c release` both pass.
- `swift test --filter DockIconRendererPixelLengthTests`, `--filter DockIconRenderKeyPixelLengthTests`, `--filter DockIconPreviewMetricsTests`, `--filter DockIconPreviewCacheTests`, `--filter DockIconPreviewWiringTests`, `--filter DockIconPreviewGuideTests` pass.
- `DockIconPreviewWiringTests.aSliderDragRendersThePreviewOnce` proves 21 Settings body re-evaluations produce exactly one 60 px render.
- `DockIconPreviewCacheTests.theCachePathReproducesTheDockRasterByteForByte` and `DockIconRendererPixelLengthTests.explicitDockPixelLengthMatchesTheDefaultRaster` prove the real Dock raster is unchanged.
- `DockIconPreviewWiringTests.thePreviewKeyCarriesTheSameIconInputsAsTheDockKey` proves the preview and the Dock icon are driven by the same `SettingsStore` derivation, so the menu bar/Dock parity rule holds.
- The non-publishing release preflight passes (Step 4 of Task 6), because the change touches `@MainActor` types and SwiftUI bindings.
- The idle `sample` capture from Task 6 Step 3 is recorded with the change.

## Out of Scope

- The real Dock-icon path in `AppIconController` (its `DockIconRenderCache`, `DockIconImageCache` and `IconRenderCoalescer` usage). It keeps the 512 px raster, its keys are unchanged, and it is not rewritten to share the preview cache.
- `MenuBarPreviewBar`'s menu bar bitmap (`Sources/StatusTrioCore/UI/IconPreviewComponents.swift:54-64`). `StatusIconRenderer.image` returns a lazily drawn `NSImage`, so it is not the 1 MiB allocation this plan removes; caching it is a separate change.
- Key normalization for `volumeArcProgress` and the quantization policy of the *menu bar* render key: owned by the render-key plan (`2026-09-20-menubar-render-key-normalization.md`).
- Exhaustive icon-option parity enumeration and lifecycle/teardown test coverage: owned by `2026-09-20-icon-parity-and-lifecycle-tests.md` (finding R-19).
- Release notes: this plan changes no user-visible behaviour (same artwork, same settings), so no `release-notes/1.3.0/*` entry is required.

## File Ownership & Conflicts

- Owned by this plan (per the review index §2, finding R-04): `Sources/StatusTrioCore/UI/Icon/DockIconRenderer.swift`, `Sources/StatusTrioCore/UI/IconPreviewComponents.swift`, `Sources/StatusTrioCore/UI/Settings/StatusIconPreviewCard.swift`, `Sources/StatusTrioCore/UI/IconGuideView.swift`, plus the new `Sources/StatusTrioCore/UI/Icon/DockIconPreviewCache.swift` and the new test files `DockIconRendererPixelLengthTests.swift`, `DockIconPreviewCacheTests.swift`, `DockIconPreviewWiringTests.swift`, `DockIconPreviewGuideTests.swift`.
- `Sources/StatusTrioCore/UI/Settings/SettingsVisualPreviews.swift` and `Sources/StatusTrioCore/UI/Settings/AppIconSectionView.swift` are listed as R-04-owned but are deliberately **not modified**: the Dock background group builds `DockIconPreviewTile`s (`SettingsVisualPreviews.swift:189-228`) and the pane builds the preview card (`AppIconSectionView.swift:16-20`), and both inherit the shared cache through the tile defaults. Do not add a cache parameter to them in this plan.
- `Sources/StatusTrioCore/UI/Icon/DockIconRenderCache.swift` is shared with R-19 (`2026-09-20-icon-parity-and-lifecycle-tests.md`), which may only change production code there if a new test proves a bug. R-04 lands first (index §3.1); this plan adds the `pixelLength` field and nothing else. Rebase R-19 on top of it.
- `Tests/StatusTrioCoreTests/DockIconRenderCacheTests.swift` and `Tests/StatusTrioCoreTests/Issue13IconParityTests.swift` are R-19-owned and must stay untouched here. Task 2 Step 5 runs the former unmodified as the proof that the defaulted parameter kept Dock keys identical.
- `Sources/StatusTrioCore/UI/Icon/StatusBarRenderCache.swift` and `Sources/StatusTrioCore/UI/StatusBarController.swift` belong to R-07/R-18; this plan does not touch them.
- Consumers in other plans that must keep compiling: `2026-09-20-menubar-render-key-normalization.md` (R-07) builds `DockIconRenderKey(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` keys and asserts that a pixel-size field added here keeps its parity test green; `2026-09-20-icon-parity-and-lifecycle-tests.md` (R-19) calls `DockIconRenderer.image(status:options:connectionOptions:volumeOptions:bluetoothAudioOptions:backgroundStyle:)` and the same `DockIconRenderKey` initializer directly, and states that R-04 lands first. Both keep working because `pixelLength` is a defaulted trailing parameter; if a rebase ever needs it explicitly, pass `DockIconRenderer.pixelSize` for Dock-side callers.
- Later plans that must rebase on this one: any plan adding a new `DockIconRenderer` call site must pass an explicit `pixelLength` or accept the 512 default knowingly.
