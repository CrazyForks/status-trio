import Foundation
import Sparkle
import Testing
@testable import StatusTrioCore

@MainActor
struct UpdateFallbackUserDriverTests {
    @Test
    func suppressesUpdaterErrorWhenNextSourceIsAvailable() {
        var presentedErrorCode: Int?
        var suppressionErrorCode: Int?
        var acknowledgementCount = 0
        let error = URLError(.cannotConnectToHost)
        let driver = UpdateFallbackUserDriver(
            hostBundle: .main,
            delegate: nil,
            presentUpdaterError: { error, acknowledgement in
                presentedErrorCode = (error as? URLError)?.code.rawValue
                acknowledgement()
            }
        )
        driver.shouldSuppressUpdaterError = { error in
            suppressionErrorCode = (error as? URLError)?.code.rawValue
            return true
        }

        driver.showUpdaterError(error) {
            acknowledgementCount += 1
        }

        #expect(presentedErrorCode == nil)
        #expect(suppressionErrorCode == error.code.rawValue)
        #expect(acknowledgementCount == 1)
    }

    @Test
    func presentsUpdaterErrorWhenFallbackIsExhausted() {
        var presentedErrorCode: Int?
        var acknowledgementCount = 0
        let error = URLError(.timedOut)
        let driver = UpdateFallbackUserDriver(
            hostBundle: .main,
            delegate: nil,
            presentUpdaterError: { error, acknowledgement in
                presentedErrorCode = (error as? URLError)?.code.rawValue
                acknowledgement()
            }
        )
        driver.shouldSuppressUpdaterError = { _ in false }

        driver.showUpdaterError(error) {
            acknowledgementCount += 1
        }

        #expect(presentedErrorCode == error.code.rawValue)
        #expect(acknowledgementCount == 1)
    }
}
