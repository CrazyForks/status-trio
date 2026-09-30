import AudioToolbox
import XCTest
@testable import StatusTrioCore

@MainActor
final class PanelActionRoutingTests: XCTestCase {
    func testOutputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [makeOutput(id: 7, uid: "old")]
        var selected: [AudioOutputDevice] = []
        let actions = StatusPanelActions(
            outputDevices: { devices },
            selectOutput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 7, uid: "old")

        devices = []
        actions.selectOutput(oldKey)
        devices = [makeOutput(id: 7, uid: "replacement")]
        actions.selectOutput(oldKey)
        actions.selectOutput(PanelAudioDeviceID(id: 7, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testInputSelectionIgnoresRemovedDeviceAndReusedIDWithDifferentUID() {
        var devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "old", name: "Mic")]
        var selected: [AudioInputDevice] = []
        let actions = StatusPanelActions(
            inputDevices: { devices },
            selectInput: { selected.append($0) }
        )
        let oldKey = PanelAudioDeviceID(id: 9, uid: "old")

        devices = []
        actions.selectInput(oldKey)
        devices = [AudioInputDevice(id: AudioDeviceID(9), uid: "replacement", name: "Mic")]
        actions.selectInput(oldKey)
        actions.selectInput(PanelAudioDeviceID(id: 9, uid: nil))

        XCTAssertEqual(selected.map(\.uid), ["replacement"])
    }

    func testActionsClampFiniteScalarsFlushAndForwardEachCommandOnce() {
        var outputScalars: [Double] = []
        var inputScalars: [Double] = []
        var finishes = 0
        var muteToggles = 0
        var inputMuteToggles = 0
        let actions = StatusPanelActions(
            setVolume: { outputScalars.append($0) },
            finishVolumeAdjustment: { finishes += 1 },
            toggleMute: { muteToggles += 1 },
            setInputScalar: { inputScalars.append($0) },
            toggleInputMute: { inputMuteToggles += 1 }
        )

        actions.setVolume(0.64)
        actions.setVolume(2)
        actions.setVolume(.infinity)
        actions.finishVolumeAdjustment()
        actions.toggleMute()
        actions.setInputScalar(-1)
        actions.setInputScalar(.nan)
        actions.toggleInputMute()

        XCTAssertEqual(outputScalars, [0.64, 1])
        XCTAssertEqual(inputScalars, [0])
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(muteToggles, 1)
        XCTAssertEqual(inputMuteToggles, 1)
    }

    private func makeOutput(id: UInt32, uid: String?) -> AudioOutputDevice {
        AudioOutputDevice(id: AudioDeviceID(id), name: "Speaker", uid: uid, isCurrent: false)
    }
}
