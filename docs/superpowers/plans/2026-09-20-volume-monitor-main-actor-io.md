# Volume Monitor Main-Actor IO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the menu bar run loop from doing synchronous CoreAudio HAL IPC: run `CoreAudioVolumeEventMonitor`'s listener reconciliation on a dedicated serial queue instead of the main actor, and make `VolumeMonitor.deinit` / `WiFiMonitor.deinit` safe on whatever thread releases the last reference.

**Architecture:** `VolumeMonitor.performRefresh(includeOutputDevices:)` (`Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift:894`) calls `eventMonitor.reconcile()` at line 903 — before the guarded background read that is armed at line 909. `CoreAudioVolumeEventMonitor` is `@MainActor` (`VolumeMonitor.swift:454-455`), so every one of those calls — the 5 s fallback poll, popover open, every volume/mute key press, and wake recovery — performs synchronous `coreaudiod` round-trips on the main thread: `client.validDefaultOutputDevice()` (`:514`, which itself is default-device + class + aliveness checks, `:88-99`), up to six `client.hasProperty` probes (`:607`), and up to seven `AudioObjectAddPropertyListenerBlock` registrations (`:640`, `:668`). A blocked main thread also stops `ReadWatchdog` from firing, because `ReadWatchdog.arm` implements its timeout as `Task { @MainActor … }` (`Sources/StatusTrioCore/Monitoring/ReadWatchdog.swift:55-69`); the watchdog protects the background read, not this listener maintenance. The fix keeps the `VolumeEventMonitoring` protocol (and therefore every existing test fake) exactly as it is, and splits the production conformer into a main-actor façade plus a nonisolated, queue-confined `CoreAudioListenerMaintenance` helper, so each protocol method returns immediately after enqueuing. `deinit` becomes nonisolated-safe by touching only thread-safe teardown-owned state and delegating listener removal to the helper's own `deinit`. The same defect class in `WiFiMonitor.deinit` (`WiFiMonitor.swift:373-380`, which mutates a non-thread-safe `CWWiFiClient` from an arbitrary thread) is closed by serializing `CoreWLANWiFiEventMonitor`'s client access.

**Tech Stack:** Swift 6 SwiftPM package (`swift-tools-version: 6.0`, `platforms: [.macOS(.v15)]`), Swift Concurrency (`@MainActor`, `Sendable`), GCD (`DispatchQueue`), CoreAudio, CoreWLAN, XCTest.

**Spec:** Derived from the 2026-09-20 code review; cross-plan index: docs/superpowers/plans/2026-09-20-review-findings-index.md (finding **R-06**, severity P6 Medium).

## Global Constraints

- CI acceptance toolchain is the `macos-26` runner with Xcode 26.6 / Swift 6.3.3. The local machine is Xcode 27 / Swift 6.4 — a local build is NOT proof that CI compiles.
- Forbidden in this repo: `isolated deinit`, enabling `IsolatedDeinit`, `weak let` (use `weak var`), passing actor-isolated methods directly as function values (use an explicit closure), assuming `Bundle.module` casing. `docs/swift-ci-compatibility.md` records CI failures caused by each of these; read it before you start.
- Run `swift test` and `swift build -c release` before committing Swift changes.
- These plans touch actors/`deinit`, so a non-publishing release preflight is mandatory: `gh workflow run release.yml --repo lingyired/status-trio --ref <branch> -f version=1.3.0 -f build=12 -f publish=false` then `gh run watch <run-id> --repo lingyired/status-trio --exit-status`.
- Every failed CI run must be recorded in `docs/swift-ci-compatibility.md` (run ID, failed stage, root cause, fix, verification).
- Tests are mixed: most use Swift Testing (`import Testing`, `@Test`, `#expect`), some XCTest. Match the file you extend. In this repo 22 of 89 test files use Swift Testing, and all four files this plan touches are XCTest (`VolumeMonitorTests.swift:1-5`, `VolumeMonitorAsyncTests.swift:1-6`, `WiFiClassifierTests.swift`) — read them before writing tests into the plan.
- No new dependencies. No new timers, no polling, and no `Task.sleep`-based synchronization in production code.
- Do not weaken `ReadWatchdog`'s documented trade-off (`ReadWatchdog.swift:1-18`: an abandoned read leaks one blocked worker thread per capped interval). This plan must not add another abandoned-thread source.
- `nonisolated(unsafe)` is allowed only for teardown-owned storage, and the reason must be stated in a comment next to the declaration.
- Do not add `MainActor.assumeIsolated` anywhere new; `docs/swift-ci-compatibility.md` and `AGENTS.md` both treat it as a latent trap when the calling thread is not guaranteed.

## Review Focus

- **Popover open or volume key press while `coreaudiod` is slow.** Every volume/mute key press reaches `VolumeMonitor.performRefresh` (`VolumeMonitor.swift:894`) through the `onVolumeChange` callback registered at `:799-801`, and the popover reaches it through `SystemStatusStore.setPopoverVisible(true)` → `refreshAll()` (`Sources/StatusTrioCore/Store/SystemStatusStore.swift:272-290`, `:321-326`). The user sees a frozen menu bar, and the watchdog cannot rescue it. Pinned by `testReconcileRunsOnTheMaintenanceQueueInsteadOfTheCaller` and `testBlockedListenerMaintenanceDoesNotBlockTheMainActor`.
- **Output device switch followed immediately by a volume key.** The listeners must be re-pointed at the new device before the UI acts on the change. Pinned by `testDefaultDeviceChangeMigratesListenersUsingExactOperations` (rewritten to drain the maintenance queue) and `testEventMonitorReconcileRepairsPartialDeviceRegistration`.
- **Teardown on a non-main thread.** `SystemStatusStore.deinit` (`SystemStatusStore.swift:78-85`) does not call `stop()`, so releasing the store releases `volumeMonitor` (`:21`) on whatever thread drops the last reference; `VolumeMonitor.deinit` currently wraps its body in `MainActor.assumeIsolated` (`VolumeMonitor.swift:781-789`), which is a fatal assertion, not a hop. Pinned by `testReleasingTheMonitorOffTheMainThreadFinishesTheStream`.
- **Wake-from-sleep recovery.** `NSWorkspace.didWakeNotification` → `recoverAll()` → `volumeMonitor.recover()` (`SystemStatusStore.swift:94-103`, `:328-333`) → `eventMonitor.recover()` (`VolumeMonitor.swift:816-821`), which removes and re-adds every listener. Pinned by `testEventMonitorRecoverRemovesAndReinstallsListeners` and `testVolumeCallbackRefreshes`.
- **Wi-Fi teardown racing a CoreWLAN recovery.** Releasing a `WiFiMonitor` off-main mutates `CWWiFiClient` through `eventMonitor.stop()` (`WiFiMonitor.swift:375-377`, `:166-168`) while the main actor can be inside `restart()` (`:160-164`). Pinned by `testCoreWLANEventMonitorSerializesClientAccessAcrossThreads`.

---

### Task 1: Run CoreAudio listener maintenance on a serial queue

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Test: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`

**Interfaces:**
- Produces: `CoreAudioClient: AnyObject, Sendable` (the client is used from the reader's utility queue today and from the maintenance queue after this task).
- Produces: `CoreAudioListenerMaintenance` — nonisolated, `@unchecked Sendable`, all mutable state confined to its injected serial queue; public methods `start(onDefaultDeviceChange:onVolumeChange:)`, `reconcile()`, `recover()`, `stop()` only enqueue.
- Produces: `CoreAudioVolumeEventMonitor.init(client:callbackQueue:maintenanceQueue:)`; existing `init(client:callbackQueue:)` call sites keep compiling through the default argument, and Step 6 passes an explicit queue so each test can drain it.
- Produces test seams: `FakeCoreAudioClient.onHasProperty`, `waitForMaintenance(_:timeout:until:)`.
- Keeps: `VolumeEventMonitoring` (`VolumeMonitor.swift:443-452`) unchanged, so `FakeVolumeEventMonitor` (`VolumeMonitorTests.swift:757-795`) and `AsyncVolumeEvents` (`VolumeMonitorAsyncTests.swift:377-395`) are untouched.

- [ ] **Step 1: Add the two failing tests to `VolumeMonitorTests.swift`**

Insert after `testDefaultDeviceChangeMigratesListenersUsingExactOperations` (currently ends at line 656, before `private func makeReading`):

```swift
    // MARK: - Listener maintenance runs off the main actor

    func testReconcileRunsOnTheMaintenanceQueueInsteadOfTheCaller() async {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            42,
            scalar: 0.5,
            isMuted: false,
            name: "Speakers",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        let maintenance = DispatchQueue(label: "test.listener-maintenance")
        let events = CoreAudioVolumeEventMonitor(client: client, maintenanceQueue: maintenance)
        let monitor = VolumeMonitor(
            statusReader: InlineAudioStatusReader(
                reader: FakeVolumeReader(result: makeReading(scalar: 0.5))
            ),
            eventMonitor: events
        )

        monitor.start()

        XCTAssertTrue(
            client.addAttempts.isEmpty,
            "Listener maintenance is synchronous HAL IPC and must not run on the caller"
        )

        let ranOnTheQueue = await waitForMaintenance(maintenance) { !client.addAttempts.isEmpty }
        XCTAssertTrue(ranOnTheQueue, "Reconcile must still run, on the maintenance queue")

        monitor.stop()
        _ = await waitForMaintenance(maintenance) { !client.removals.isEmpty }
    }

    func testBlockedListenerMaintenanceDoesNotBlockTheMainActor() async {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            42,
            scalar: 0.5,
            isMuted: false,
            name: "Speakers",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        let maintenance = DispatchQueue(label: "test.listener-maintenance")
        let gate = DispatchSemaphore(value: 0)
        let calls = ReadCounter()
        let startedOffMain = expectation(description: "listener maintenance started off the main thread")
        let startedOnMain = expectation(description: "listener maintenance started on the main thread")
        startedOnMain.isInverted = true
        client.onHasProperty = {
            if Thread.isMainThread {
                startedOnMain.fulfill()
            } else {
                startedOffMain.fulfill()
            }
            if calls.increment() == 1 {
                _ = gate.wait(timeout: .now() + 5)
            }
        }
        let events = CoreAudioVolumeEventMonitor(client: client, maintenanceQueue: maintenance)
        let monitor = VolumeMonitor(
            statusReader: InlineAudioStatusReader(
                reader: FakeVolumeReader(result: makeReading(scalar: 0.5))
            ),
            eventMonitor: events
        )

        monitor.start()
        await fulfillment(of: [startedOffMain, startedOnMain], timeout: 5)

        // The heartbeat is the positive half: it can only run because the main
        // actor is free while `coreaudiod` is still answering the blocked probe.
        let heartbeat = expectation(description: "MainActor keeps running during listener maintenance")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 5)

        gate.signal()
        monitor.stop()
        _ = await waitForMaintenance(maintenance) { !client.removals.isEmpty }
    }
```

- [ ] **Step 2: Add the shared drain helper and the fake's probe hook**

Append to the same file, next to `BlockingAudioRead` (currently lines 727-754):

```swift
/// Drains a serial maintenance queue until `condition` holds. A drain that is
/// enqueued after a hop is ordered behind that hop, so this is a real barrier;
/// the bounded poll turns a regression into a failed assertion instead of a hang.
@MainActor
private func waitForMaintenance(
    _ queue: DispatchQueue,
    timeout: TimeInterval = 5,
    until condition: () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Carries one retained reference to another thread so a test can choose the
/// thread that performs the last release.
private final class RetainedReference: @unchecked Sendable {
    private let unmanaged: Unmanaged<AnyObject>

    init(_ object: AnyObject) {
        unmanaged = Unmanaged.passRetained(object)
    }

    func release() {
        unmanaged.release()
    }
}
```

Then, in `FakeCoreAudioClient` (currently line 811), change the declaration and add the hook:

```swift
/// `@unchecked Sendable`: mutated only on the listener-maintenance queue (or on
/// the main actor in the reader-only tests, which never run a maintenance hop),
/// and read by tests only after `waitForMaintenance` has drained that queue.
private final class FakeCoreAudioClient: CoreAudioClient, @unchecked Sendable {
    ...
    /// Test hook, called at the start of `hasProperty`. Set it before the monitor
    /// is started: the enqueue of the first maintenance hop orders this write
    /// before the read on the maintenance queue.
    var onHasProperty: (() -> Void)?
```

and inside `hasProperty` (currently lines 1041-1053) call it first:

```swift
    func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        onHasProperty?()
        return availableProperties.contains(propertyKey(
            objectID: objectID,
            selector: selector,
            scope: scope,
            element: element
        ))
    }
```

- [ ] **Step 3: Run the tests and verify RED**

Run: `swift test --filter VolumeMonitorTests/testReconcileRunsOnTheMaintenanceQueueInsteadOfTheCaller`
Expected: compile failure — `extra argument 'maintenanceQueue' in call`, and `value of type 'FakeCoreAudioClient' has no member 'onHasProperty'`.

Run: `swift test --filter VolumeMonitorTests/testBlockedListenerMaintenanceDoesNotBlockTheMainActor`
Expected: the same compile failure.

- [ ] **Step 4: Add the queue seam only, then verify the behavioural RED**

Add the `maintenanceQueue` parameter to `CoreAudioVolumeEventMonitor.init` and store it in a `private let maintenanceQueue: DispatchQueue`, but leave `reconcile()`/`start()`/`recover()`/`stop()` calling the existing `@MainActor` bodies unchanged.

Run: `swift test --filter VolumeMonitorTests/testReconcileRunsOnTheMaintenanceQueueInsteadOfTheCaller`
Expected: FAIL — `XCTAssertTrue failed - Listener maintenance is synchronous HAL IPC and must not run on the caller`, because `reconcile()` still runs inline on the main actor.

Run: `swift test --filter VolumeMonitorTests/testBlockedListenerMaintenanceDoesNotBlockTheMainActor`
Expected: FAIL after the 5 s timeout on `startedOffMain`, with `startedOnMain` unexpectedly fulfilled — the probe ran on the main thread.

- [ ] **Step 5: Move the client work into the queue-confined helper**

In `VolumeMonitor.swift`, replace `protocol CoreAudioClient: AnyObject {` (line 33) with:

```swift
/// Clients are used from `CoreAudioStatusReader`'s utility queue and, after
/// R-06, from the listener-maintenance queue, so every conformer must be safe to
/// use off the main actor.
protocol CoreAudioClient: AnyObject, Sendable {
```

Change `final class CoreAudioSystemClient: CoreAudioClient {` (line 101) to:

```swift
/// Stateless: every call opens its own `AudioObjectGetPropertyData` request, so
/// the value carries no shared mutable state across threads.
final class CoreAudioSystemClient: CoreAudioClient, Sendable {
```

Then replace the whole `CoreAudioVolumeEventMonitor` class (lines 454-725) with this façade plus helper. `DeviceListenerKey`, `ListenerRegistration`, `reconcileDeviceListener`, `addDefaultDeviceListener`, `addDeviceListener`, `removeAllListeners`, `removeDeviceListeners`, `removeListener` and `unregister` keep their current bodies; only the isolation and the four entry points change.

```swift
/// Main-actor façade over `CoreAudioListenerMaintenance`.
///
/// Every method returns after enqueuing work, so the menu bar run loop never
/// waits on `coreaudiod`. The `VolumeEventMonitoring` protocol stays `@MainActor`
/// and every test fake stays valid.
@MainActor
final class CoreAudioVolumeEventMonitor: VolumeEventMonitoring {
    private let maintenance: CoreAudioListenerMaintenance

    init(
        client: any CoreAudioClient = CoreAudioSystemClient(),
        callbackQueue: DispatchQueue? = .main,
        maintenanceQueue: DispatchQueue = DispatchQueue(
            label: "StatusTrio.VolumeListenerMaintenance",
            qos: .utility
        )
    ) {
        maintenance = CoreAudioListenerMaintenance(
            client: client,
            callbackQueue: callbackQueue,
            maintenanceQueue: maintenanceQueue
        )
    }

    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {
        maintenance.start(
            onDefaultDeviceChange: onDefaultDeviceChange,
            onVolumeChange: onVolumeChange
        )
    }

    /// Never blocks: `AudioObjectHasProperty` and the listener add/remove calls
    /// are synchronous IPC to `coreaudiod` and run on the maintenance queue.
    func reconcile() {
        maintenance.reconcile()
    }

    func recover() {
        maintenance.recover()
    }

    func stop() {
        maintenance.stop()
    }
}

/// Owns the CoreAudio property listeners for the default output device.
///
/// Invariants, in the order they matter:
/// - All mutable state is confined to `queue`. `AudioObjectHasProperty`,
///   `AudioObjectAddPropertyListenerBlock` and
///   `AudioObjectRemovePropertyListenerBlock` are synchronous HAL round-trips;
///   running them on the main actor blocks the menu bar run loop and starves
///   `ReadWatchdog`, whose timer is a main-actor task.
/// - Every enqueued block captures `self` strongly, so `deinit` can only run
///   after the last block finished and may therefore read the state below from
///   whatever thread releases the last reference.
/// - The listener blocks are delivered on `callbackQueue` and only enqueue a hop;
///   they never touch state directly.
/// - `@unchecked Sendable` states that confinement; the compiler cannot check it.
final class CoreAudioListenerMaintenance: @unchecked Sendable {
    private struct DeviceListenerKey: Hashable {
        let selector: AudioObjectPropertySelector
        let element: AudioObjectPropertyElement
    }

    /// `@unchecked Sendable`: the registration is only ever handed back to
    /// `AudioObjectRemovePropertyListenerBlock` on the queue that created it.
    private struct ListenerRegistration: @unchecked Sendable {
        let key: DeviceListenerKey
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let queue: DispatchQueue?
        let block: AudioObjectPropertyListenerBlock
    }

    private let client: any CoreAudioClient
    private let callbackQueue: DispatchQueue?
    private let queue: DispatchQueue
    private var defaultDeviceRegistration: ListenerRegistration?
    private var deviceRegistrations: [ListenerRegistration] = []
    private var registeredDeviceID: AudioDeviceID?
    private var deviceNeedsReconciliation = true
    private var onDefaultDeviceChange: (@MainActor @Sendable () -> Void)?
    private var onVolumeChange: (@MainActor @Sendable () -> Void)?
    private var isStarted = false
    private var isStopped = false

    init(
        client: any CoreAudioClient,
        callbackQueue: DispatchQueue?,
        maintenanceQueue: DispatchQueue
    ) {
        self.client = client
        self.callbackQueue = callbackQueue
        self.queue = maintenanceQueue
    }

    deinit {
        // No enqueued block can be running here, because each one captures `self`
        // strongly. Unregistration is enqueued instead of performed inline:
        // `AudioObjectRemovePropertyListenerBlock` is synchronous HAL IPC and
        // `deinit` may run on any thread.
        let client = client
        let registrations = ([defaultDeviceRegistration].compactMap { $0 } + deviceRegistrations)
        guard !registrations.isEmpty else { return }
        queue.async {
            for registration in registrations {
                Self.unregister(registration, client: client)
            }
        }
    }

    func start(
        onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
        onVolumeChange: @escaping @MainActor @Sendable () -> Void
    ) {
        queue.async { [self] in
            guard !isStarted, !isStopped else { return }
            isStarted = true
            self.onDefaultDeviceChange = onDefaultDeviceChange
            self.onVolumeChange = onVolumeChange
            deviceNeedsReconciliation = true
            reconcileOnQueue()
        }
    }

    func reconcile() {
        queue.async { [self] in
            reconcileOnQueue()
        }
    }

    func recover() {
        queue.async { [self] in
            guard isStarted, !isStopped else { return }
            removeAllListeners()
            registeredDeviceID = nil
            deviceNeedsReconciliation = true
            reconcileOnQueue()
        }
    }

    func stop() {
        queue.async { [self] in
            guard !isStopped else { return }
            isStopped = true
            removeAllListeners()
            registeredDeviceID = nil
            deviceNeedsReconciliation = true
            onDefaultDeviceChange = nil
            onVolumeChange = nil
        }
    }

    // MARK: - Maintenance queue

    private func reconcileOnQueue() {
        guard isStarted, !isStopped else { return }

        reconcileDefaultDeviceListener()

        let currentDeviceID = client.validDefaultOutputDevice()
        if deviceNeedsReconciliation || currentDeviceID != registeredDeviceID {
            removeDeviceListeners()
            registeredDeviceID = currentDeviceID
            deviceNeedsReconciliation = false
        }

        guard let currentDeviceID else { return }
        reconcileDeviceListeners(for: currentDeviceID)
    }

    private func reconcileDefaultDeviceListener() {
        guard defaultDeviceRegistration == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.queue.async { [weak self] in
                self?.defaultDeviceDidChange()
            }
        }
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        defaultDeviceRegistration = addDefaultDeviceListener(
            address: address,
            block: block
        )
    }

    private func reconcileDeviceListeners(for deviceID: AudioDeviceID) {
        let volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.queue.async { [weak self] in
                self?.volumeDidChange()
            }
        }
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.queue.async { [weak self] in
                self?.volumeDidChange()
            }
        }

        for element in CoreAudioVolumeReader.outputElements {
            reconcileDeviceListener(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: element,
                block: volumeBlock
            )
            reconcileDeviceListener(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                element: element,
                block: muteBlock
            )
        }
    }

    private func reconcileDeviceListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        let key = DeviceListenerKey(selector: selector, element: element)
        guard !deviceRegistrations.contains(where: { $0.key == key }) else {
            return
        }

        let address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        guard client.hasProperty(
            objectID: objectID,
            selector: selector,
            scope: kAudioObjectPropertyScopeOutput,
            element: element
        ) else { return }

        guard let registration = addDeviceListener(
            key: key,
            objectID: objectID,
            address: address,
            block: block
        ) else { return }
        deviceRegistrations.append(registration)
    }

    private func defaultDeviceDidChange() {
        guard isStarted, !isStopped else { return }
        deviceNeedsReconciliation = true
        reconcileOnQueue()
        deliver(onDefaultDeviceChange)
    }

    private func volumeDidChange() {
        guard isStarted, !isStopped else { return }
        deliver(onVolumeChange)
    }

    /// Runs a stored callback on the main actor. The closure value is read on the
    /// maintenance queue and carried across as a `@Sendable` closure, so the main
    /// actor never reads queue-confined state.
    private func deliver(_ callback: (@MainActor @Sendable () -> Void)?) {
        guard let callback else { return }
        Task { @MainActor in callback() }
    }

    // MARK: - Listener registration

    private func addDefaultDeviceListener(
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> ListenerRegistration? {
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        let status = client.addListener(
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to add CoreAudio default-device listener for selector \(address.mSelector, privacy: .public), element \(address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
            return nil
        }

        return ListenerRegistration(
            key: DeviceListenerKey(selector: address.mSelector, element: address.mElement),
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
    }

    private func addDeviceListener(
        key: DeviceListenerKey,
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> ListenerRegistration? {
        let status = client.addListener(
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to add CoreAudio listener for selector \(address.mSelector, privacy: .public), element \(address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
            return nil
        }

        return ListenerRegistration(
            key: key,
            objectID: objectID,
            address: address,
            queue: callbackQueue,
            block: block
        )
    }

    private func removeAllListeners() {
        if let defaultDeviceRegistration {
            removeListener(defaultDeviceRegistration)
            self.defaultDeviceRegistration = nil
        }
        removeDeviceListeners()
    }

    private func removeDeviceListeners() {
        for registration in deviceRegistrations {
            removeListener(registration)
        }
        deviceRegistrations.removeAll()
    }

    private func removeListener(_ registration: ListenerRegistration) {
        Self.unregister(registration, client: client)
    }

    nonisolated private static func unregister(
        _ registration: ListenerRegistration,
        client: any CoreAudioClient
    ) {
        let status = client.removeListener(
            objectID: registration.objectID,
            address: registration.address,
            queue: registration.queue,
            block: registration.block
        )
        if status != noErr {
            volumeMonitorLogger.error(
                "Failed to remove CoreAudio listener for selector \(registration.address.mSelector, privacy: .public), element \(registration.address.mElement, privacy: .public): OSStatus \(status, privacy: .public)"
            )
        }
    }
}
```

Note: the order inside `performRefresh` is preserved — `eventMonitor.reconcile()` is still called before the read starts (`VolumeMonitor.swift:903`), but it is now an enqueue. The read therefore no longer waits for listener registration; that is the point of the change. Every state change for the event monitor goes through the same serial queue, and `reconcile()` calls enqueue in call order, so a reconcile that was requested before `stop()` still runs before the stop block (FIFO) and the stop block removes whatever it registered.

- [ ] **Step 6: Convert the five existing event-monitor tests to the queue seam**

All five construct `CoreAudioVolumeEventMonitor(client: client)` at lines 531, 548, 566, 594 and 638. Each needs a queue of its own and a drain before it asserts:

```swift
        let maintenance = DispatchQueue(label: "test.listener-maintenance")
        let monitor = CoreAudioVolumeEventMonitor(
            client: client,
            maintenanceQueue: maintenance
        )
```

- `testEventMonitorReconcileIsNoOpBeforeStart` (line 528): mark it `async`, and after `monitor.reconcile()` add `let drained = await waitForMaintenance(maintenance) { true }; XCTAssertTrue(drained)`. The negative assertions are unchanged: a reconcile before `start()` must not reach the client even after the queue drains.
- `testEventMonitorRecoverRemovesAndReinstallsListeners` (line 539): mark it `async`; drain after `monitor.start(...)` and read `initialListeners`/`initialSuccessfulAdds` only afterwards; drain again after `monitor.recover()` before the count assertions; drain after `monitor.stop()`.
- `testEventMonitorRetriesFailedDefaultDeviceListener` (line 562): mark it `async`; drain after `start(...)`; drain after `reconcile()`; final assertions unchanged.
- `testEventMonitorReconcileRepairsPartialDeviceRegistration` (line 579): mark it `async`; drain after `start(...)` and after `reconcile()`.
- `testDefaultDeviceChangeMigratesListenersUsingExactOperations` (line 620): already `async`; replace `await fulfillment(of: [callbackExpectation], timeout: 1)` with `await fulfillment(of: [callbackExpectation], timeout: 5)`. The callback is now delivered on the main actor after the maintenance hop, and everything it asserts happens before that delivery, so no extra drain is needed. Add `_ = await waitForMaintenance(maintenance) { true }` after `monitor.stop()`.

- [ ] **Step 7: Run the tests**

Run: `swift test --filter VolumeMonitorTests`
Expected: PASS, including the two new tests and the five converted ones.

Run: `swift test --filter VolumeMonitorAsyncTests`
Expected: PASS without edits — the fake `AsyncVolumeEvents.reconcile()` is still `@MainActor` and synchronous, so every `reconcileCount` assertion (lines 16, 24) keeps its meaning.

- [ ] **Step 8: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift Tests/StatusTrioCoreTests/VolumeMonitorTests.swift
git commit -m "fix(volume): run CoreAudio listener maintenance off the main actor"
```

---

### Task 2: Make `VolumeMonitor.deinit` nonisolated-safe

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- Test: `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- Test: `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift`

**Interfaces:**
- Produces: the `VolumeMonitor` teardown contract — `deinit` is nonisolated and touches only `scheduledRefreshTask?.cancel()` and `continuation.finish()`; `stop()` owns listener teardown on the main actor; a `VolumeEventMonitoring` conformer unregisters its own listeners in its `deinit` (production: `CoreAudioListenerMaintenance.deinit` from Task 1).
- Consumes: Task 1's `CoreAudioListenerMaintenance.deinit`.

- [ ] **Step 1: Write the failing off-main release test**

Add to `VolumeMonitorTests.swift`, next to `testDeinitWithoutStopStopsEventMonitorAndFinishesUpdates` (currently line 409):

```swift
    func testReleasingTheMonitorOffTheMainThreadFinishesTheStream() async {
        let eventMonitor = FakeVolumeEventMonitor()
        var monitor: VolumeMonitor? = makeMonitor(
            reader: FakeVolumeReader(result: makeReading(scalar: 0.5)),
            eventMonitor: eventMonitor
        )
        weak var weakMonitor = monitor
        let updates = monitor!.updates
        monitor?.start()

        // Move the last reference to a background thread: `deinit` is nonisolated
        // and `MainActor.assumeIsolated` in it is a fatal assertion, not a hop.
        let reference = RetainedReference(monitor!)
        monitor = nil
        let released = expectation(description: "released off the main thread")
        DispatchQueue.global().async {
            reference.release()
            released.fulfill()
        }
        await fulfillment(of: [released], timeout: 5)

        XCTAssertNil(weakMonitor)
        var iterator = updates.makeAsyncIterator()
        let end = await iterator.next()
        XCTAssertNil(end, "The updates stream must be finished by the off-main deinit")
    }
```

- [ ] **Step 2: Run it and verify RED**

Run: `swift test --filter VolumeMonitorTests/testReleasingTheMonitorOffTheMainThreadFinishesTheStream`
Expected: the test process aborts with `Fatal error: Incorrect actor executor assumption` from `MainActor.assumeIsolated` at `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift:782`. Run only this filter: the trap takes the whole test process down.

- [ ] **Step 3: Cancel the assumeIsolated and state the new contract**

Replace `deinit` (lines 781-789) with:

```swift
    deinit {
        // `deinit` is nonisolated and runs on whatever thread releases the last
        // reference, so it must not touch main-actor state. `Task.cancel()` and
        // `Continuation.finish()` are thread-safe. Listener teardown belongs to
        // `stop()` on the main actor; `CoreAudioVolumeEventMonitor`'s helper
        // unregisters its own listeners in its deinit, and `ReadWatchdog` cancels
        // its own timer in its deinit (`ReadWatchdog.swift:37-41`).
        scheduledRefreshTask?.cancel()
        continuation.finish()
    }
```

- [ ] **Step 4: Update the two tests that asserted deinit-time teardown**

Rewrite `testDeinitWithoutStopStopsEventMonitorAndFinishesUpdates` (`VolumeMonitorTests.swift:409-426`) as:

```swift
    func testDeinitWithoutStopFinishesUpdatesWithoutTouchingTheEventMonitor() async {
        let eventMonitor = FakeVolumeEventMonitor()
        var monitor: VolumeMonitor? = makeMonitor(
            reader: FakeVolumeReader(result: makeReading(scalar: 0.5)),
            eventMonitor: eventMonitor
        )
        weak var weakMonitor = monitor
        monitor?.start()
        var iterator = monitor?.updates.makeAsyncIterator()
        _ = await iterator?.next()

        monitor = nil

        XCTAssertNil(weakMonitor)
        XCTAssertEqual(
            eventMonitor.stopCount,
            0,
            "deinit is nonisolated: teardown belongs to stop() and to the conformer's own deinit"
        )
        let finalStatus = await iterator?.next()
        XCTAssertNil(finalStatus)
    }
```

In `VolumeMonitorAsyncTests.swift`, change the assertion at line 85 of `testOutstandingReadDoesNotRetainMonitor` (line 75) to:

```swift
        XCTAssertNil(weakMonitor)
        XCTAssertEqual(
            events.stopCount,
            0,
            "An outstanding read must not retain the monitor, and deinit must not call the event monitor"
        )
```

- [ ] **Step 5: Add the production-level deinit test for the event monitor**

Add to `VolumeMonitorTests.swift`, after the converted event-monitor tests:

```swift
    func testEventMonitorUnregistersItsListenersOnDeinit() async {
        let client = FakeCoreAudioClient()
        client.configureDevice(
            42,
            scalar: 0.5,
            isMuted: false,
            name: "Speakers",
            supportedElements: [kAudioObjectPropertyElementMain]
        )
        let maintenance = DispatchQueue(label: "test.listener-maintenance")
        var events: CoreAudioVolumeEventMonitor? = CoreAudioVolumeEventMonitor(
            client: client,
            maintenanceQueue: maintenance
        )
        events?.start(onDefaultDeviceChange: {}, onVolumeChange: {})
        _ = await waitForMaintenance(maintenance) { client.hasDefaultDeviceListener }
        XCTAssertFalse(client.activeListeners.isEmpty)

        events = nil

        let removed = await waitForMaintenance(maintenance) { client.activeListeners.isEmpty }
        XCTAssertTrue(removed, "A released event monitor must unregister its own listeners")
        XCTAssertFalse(client.hasDefaultDeviceListener)
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter VolumeMonitorTests`
Run: `swift test --filter VolumeMonitorAsyncTests`
Expected: PASS. The off-main release test now reaches `deinit` on the background thread without trapping, and both stream-finish assertions hold.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift Tests/StatusTrioCoreTests/VolumeMonitorTests.swift Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift
git commit -m "fix(volume): make VolumeMonitor.deinit nonisolated-safe"
```

---

### Task 3: Serialize `CoreWLANWiFiEventMonitor` for off-main teardown

**Files:**
- Modify: `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift`
- Test: `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift`

**Interfaces:**
- Produces: `CoreWLANWiFiEventMonitor` with lock-serialized `start(delegate:events:)`, `restart(delegate:events:)`, `stop()`; the `WiFiEventMonitoring` protocol (`WiFiMonitor.swift:89-93`) and every fake stay unchanged.
- Produces: the stated reason for `WiFiMonitor`'s `nonisolated(unsafe)` teardown-owned storage (`WiFiMonitor.swift:311-312`).
- Consumes: nothing from Tasks 1-2; the two changes are independent.

- [ ] **Step 1: Write the failing serialization test**

Add to `WiFiClassifierTests.swift`, next to `testCoreWLANEventMonitorRestartRecreatesClientAndRegistersEvents` (currently line 466):

```swift
    func testCoreWLANEventMonitorSerializesClientAccessAcrossThreads() async {
        let client = OverlapDetectingCoreWLANClient()
        let eventMonitor = CoreWLANWiFiEventMonitor(clientFactory: { client })
        let delegate = FakeCWEventDelegate()
        let events: [CWEventType] = [.powerDidChange]

        // `WiFiMonitor.deinit` runs on whatever thread releases the last
        // reference and calls `eventMonitor.stop()`, while the main actor can be
        // inside `recover()` -> `restart()`. `CWWiFiClient` is not thread-safe.
        let background = expectation(description: "background stop/restart loop finished")
        DispatchQueue.global().async {
            for _ in 0..<20 {
                eventMonitor.stop()
                eventMonitor.restart(delegate: delegate, events: events)
            }
            background.fulfill()
        }
        for _ in 0..<20 {
            eventMonitor.restart(delegate: delegate, events: events)
            eventMonitor.stop()
        }
        await fulfillment(of: [background], timeout: 20)

        XCTAssertEqual(
            client.overlapCount,
            0,
            "CWWiFiClient must never be entered from two threads at once"
        )
        XCTAssertEqual(client.stopAllCount, 80, "Every stop must reach the client exactly once")
    }
```

Add the detector next to `FakeCoreWLANClient` (currently line 1338):

```swift
/// Detects concurrent entry into `CWWiFiClient`, which is what the lock in
/// `CoreWLANWiFiEventMonitor` must prevent. The sleep happens without holding the
/// lock, so a missing lock is observed instead of being hidden by the detector.
private final class OverlapDetectingCoreWLANClient: CWWiFiClient {
    private let lock = NSLock()
    private var inside = false
    private(set) var overlapCount = 0
    private(set) var stopAllCount = 0
    weak var storedDelegate: AnyObject?

    override var delegate: AnyObject? {
        get { lock.withLock { storedDelegate } }
        set { lock.withLock { storedDelegate = newValue } }
    }

    override func startMonitoringEvent(with event: CWEventType) throws {
        enter()
        defer { exit() }
    }

    override func stopMonitoringAllEvents() throws {
        enter()
        defer { exit() }
        lock.withLock { stopAllCount += 1 }
        Thread.sleep(forTimeInterval: 0.01)
    }

    private func enter() {
        lock.withLock {
            if inside { overlapCount += 1 }
            inside = true
        }
    }

    private func exit() {
        lock.withLock { inside = false }
    }
}
```

- [ ] **Step 2: Run it and verify RED**

Run: `swift test --filter WiFiClassifierTests/testCoreWLANEventMonitorSerializesClientAccessAcrossThreads`
Expected: FAIL — `XCTAssertEqual failed: ("<n>") is not equal to ("0")` for `overlapCount`, because two threads are inside `CWWiFiClient` at the same time. `stopAllCount` is already 80 today.

- [ ] **Step 3: Serialize the client**

In `WiFiMonitor.swift`, replace lines 147-193 with:

```swift
/// CoreWLAN's `CWWiFiClient` is not thread-safe. `WiFiMonitor.deinit`
/// (`:373-380`) runs on whatever thread releases the last reference and calls
/// `stop()`, while the main actor can be inside `recover()` -> `restart()`, so
/// every client mutation is serialized on `lock`.
///
/// The lock is held across the CoreWLAN calls and nowhere else. The
/// `CWEventDelegate` callbacks never re-enter this type — they only create a
/// `Task { @MainActor }` on `WiFiMonitor` — so the lock cannot deadlock.
final class CoreWLANWiFiEventMonitor: WiFiEventMonitoring {
    private let clientFactory: WiFiClientFactory
    private let lock = NSLock()
    private var client: CWWiFiClient

    init(clientFactory: @escaping WiFiClientFactory = { CWWiFiClient() }) {
        self.clientFactory = clientFactory
        self.client = clientFactory()
    }

    func start(delegate: any CWEventDelegate, events: [CWEventType]) {
        lock.withLock {
            configure(delegate: delegate, events: events)
        }
    }

    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {
        lock.withLock {
            clear()
            client = clientFactory()
            configure(delegate: delegate, events: events)
        }
    }

    func stop() {
        lock.withLock {
            clear()
        }
    }

    /// Call only while `lock` is held.
    private func configure(delegate: any CWEventDelegate, events: [CWEventType]) {
        client.delegate = delegate
        for event in events {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                wifiMonitorLogger.error(
                    "Failed to register CoreWLAN event \(event.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Call only while `lock` is held.
    private func clear() {
        client.delegate = nil
        do {
            try client.stopMonitoringAllEvents()
        } catch {
            wifiMonitorLogger.error(
                "Failed to clear CoreWLAN events: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
```

- [ ] **Step 4: State why the teardown-owned storage is safe**

Replace lines 311-312 with:

```swift
    /// `nonisolated(unsafe)`: teardown-owned. Both are read only by `deinit`,
    /// which may run on any thread. `CoreWLANWiFiEventMonitor` serializes its own
    /// client access and `NetworkWiFiPathMonitor` is lock-protected
    /// (`WiFiMonitor.swift:207-250`), so calling them from the releasing thread is
    /// safe; every other access happens on the main actor.
    nonisolated(unsafe) private let eventMonitor: any WiFiEventMonitoring
    nonisolated(unsafe) private let pathMonitor: any WiFiPathMonitoring
```

Also extend `WiFiMonitor.deinit` (`:373-380`) with the contract comment, leaving the body unchanged:

```swift
    deinit {
        // Nonisolated: `stop()` and `cancel()` below are the only work this may do
        // off the main actor. Both callees are thread-safe by construction.
        scheduledRefreshTask?.cancel()
        if lifecycle != .stopped {
            eventMonitor.stop()
            pathMonitor.cancel()
            continuation.finish()
        }
    }
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter WiFiClassifierTests`
Expected: PASS, including the new test, `testCoreWLANEventMonitorRestartRecreatesClientAndRegistersEvents` (line 466), `testStopIsIdempotentAndFinishesUpdates` (line 755) and `testDeinitWithoutStopTearsDownAndFinishesUpdates` (line 693), which are unchanged by design.

Run: `swift test --filter VolumeMonitorTests`
Expected: PASS (no interaction with Task 1).

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift Tests/StatusTrioCoreTests/WiFiClassifierTests.swift
git commit -m "fix(wifi): serialize CoreWLAN event monitor client access for off-main teardown"
```

---

### Task 4: Full verification

**Files:**
- No production files.

- [ ] **Step 1: Run the full suite**

Run: `swift test`
Expected: all tests pass. Note the suite count in the commit/PR text (the review baseline is 149 tests / 26 suites).

- [ ] **Step 2: Run the release build**

Run: `swift build -c release`
Expected: successful build. The app must still build against the macOS 26 SDK or newer; do not touch `scripts/build-app.sh` or `scripts/verify-platform-version.sh`.

- [ ] **Step 3: Measure the fix on the main thread**

Build and launch the app, then sample the main thread while driving the volume key path:

```bash
sample StatusTrio 5 -file /tmp/st-main-after.txt
```

Expected: `CoreAudioListenerMaintenance` / `AudioObjectGetPropertyData` frames appear on the `StatusTrio.VolumeListenerMaintenance` queue, never on the main thread. Capture the same sample from `main` before the change for the comparison and paste both counts into the commit or PR text. If `scripts/check-forbidden-patterns.sh` exists by then (finding R-18), run it and expect no findings.

- [ ] **Step 4: Run the non-publishing release preflight**

Run:

```bash
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref fix/volume-monitor-main-actor-io \
  -f version=1.3.0 \
  -f build=12 \
  -f publish=false

gh run watch <run-id> --repo lingyired/status-trio --exit-status
```

Expected: workflow passes without publishing. The change touches `@MainActor`, `Sendable` and `deinit`, so this preflight is the acceptance gate, not the local build.

- [ ] **Step 5: Record the preflight and any failure**

Append the preflight result to `docs/swift-ci-compatibility.md` following the existing per-run convention (run ID, stage results, version/build, whether anything was published). If any stage fails, record run ID, failed stage, root cause, fix and the verification run that followed — a rerun that passes is not a root cause.

- [ ] **Step 6: Commit**

```bash
git add docs/swift-ci-compatibility.md
git commit -m "docs: record the R-06 main-actor audio preflight"
```

## Verification

- [ ] `swift test` passes; `swift test --filter VolumeMonitorTests`, `--filter VolumeMonitorAsyncTests` and `--filter WiFiClassifierTests` each pass on their own.
- [ ] `swift build -c release` succeeds on the macOS 26-or-newer SDK.
- [ ] `git diff --check` reports no whitespace errors, and `git status --short` lists only the five files this plan owns.
- [ ] `CoreAudioListenerMaintenance` is the only place that touches `any CoreAudioClient` for listener work, and no `AudioObject*` call can be reached from a `@MainActor` method: `grep -n "client\." Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` shows the calls inside `CoreAudioListenerMaintenance` only.
- [ ] `grep -n "assumeIsolated" Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift` returns nothing.
- [ ] `grep -n "nonisolated(unsafe)" Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift` returns nothing for `VolumeMonitor.swift` (the helper is `@unchecked Sendable` with a stated invariant) and returns exactly the two documented `WiFiMonitor` teardown-owned declarations.
- [ ] `sample StatusTrio 5` shows no HAL IPC on the main thread while a volume key is held.
- [ ] Non-publishing release preflight passes, and its run ID is recorded in `docs/swift-ci-compatibility.md`.
- [ ] No `isolated deinit`, no `weak let`, no actor-isolated method passed as a function value, and no new `MainActor.assumeIsolated` in the diff.

## Out of Scope

- **Re-arming reconciliation only from the already-registered `kAudioHardwarePropertyDefaultOutputDevice` listener.** The review offered it as an alternative; once the work runs off the main actor it buys nothing, and it would remove the repair path covered by `testEventMonitorReconcileRepairsPartialDeviceRegistration` and `testEventMonitorRetriesFailedDefaultDeviceListener`. Do not add it.
- **Restructuring `ReadWatchdog`.** Its header (`ReadWatchdog.swift:1-18`) documents the abandoned-worker-thread trade-off as deliberate; this plan must not change the backoff, the cap, or the timeout mechanism.
- **`WiFiMonitor`'s read/scan path.** `recover()`/`restart()` logic, `startPathMonitoring`, the stale-interval recovery loop and `CoreWLANWiFiEventMonitor.configure/clear` bodies belong to finding R-02. This plan only adds the lock and the comments.
- **The other `MainActor.assumeIsolated` call sites** — `StatusBarController.swift:343`, `MainMenuController.swift:96`, `SystemIconAppearanceMonitor.swift:46,73`. They run inside notification/event handlers that are documented to be main-thread-bound, and `StatusBarController.swift` is owned by R-18.
- **Release-notes entries.** `release-notes/1.3.0/en.md` and `zh-Hans.md` are shared single-writer files owned by the plans that batch user-facing notes (R-09, R-13). If the coordinator wants a line for the responsiveness fix, add it in that batch, not here.
- **A UI regression test for the popover.** There is no AppKit-level test harness for "the popover opens fast"; the queue assertion plus the `sample` measurement are the evidence this plan provides.

## File Ownership & Conflicts

**Owns (exclusive):**
- `Sources/StatusTrioCore/Monitoring/VolumeMonitor.swift`
- `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift`
- `Tests/StatusTrioCoreTests/VolumeMonitorAsyncTests.swift`

**Owns (partial, finding R-06 scope only):** `Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift` — the `deinit` comment (`:373-380`), the `nonisolated(unsafe)` reason comments (`:311-312`) and `CoreWLANWiFiEventMonitor` (`:147-193`). Per the cross-plan index, R-02 (Wi-Fi scan cadence) also modifies this file: **either order, never simultaneously**. R-02 must not touch `deinit`, the `nonisolated(unsafe)` storage, or `CoreWLANWiFiEventMonitor`; this plan must not touch `recover()`, `restart()` call sites, the stale-interval loop or the scan cadence.

**Shared:**
- `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift` — this plan adds one test and one fake, additively, at lines 466+ and 1338+. R-02 owns the Wi-Fi test changes; sequence the two plans and re-run `swift test --filter WiFiClassifierTests` after the rebase.
- `Tests/StatusTrioCoreTests/VolumeMonitorTests.swift` and `VolumeMonitorAsyncTests.swift` — R-20 (compiler warning cleanup) touches the `weak var` lines at `VolumeMonitorTests.swift:415` and `VolumeMonitorAsyncTests.swift:79`. **This plan lands first** (per the index, §3.1): Task 2 rewrites the test around line 415 and edits line 79, so R-20 rebases onto the new text.
- `docs/swift-ci-compatibility.md` — append-only, shared with every plan. Add one section for this plan's preflight; never rewrite existing rows.

**Does not touch:** `Store/SystemStatusStore.swift` (the call sites at `:272-290`, `:321-326`, `:328-333` are read-only evidence), `App/AppEnvironment.swift`, `Monitoring/AudioStatusReader.swift`, `Monitoring/ReadWatchdog.swift`, `scripts/*`, `.github/workflows/*`, `release-notes/*`, `appcast.xml`.
