import Testing
@testable import StatusTrioCore

struct AppIconPlacementTests {
    @Test(arguments: AppIconPlacement.allCases)
    func visibility(placement: AppIconPlacement) {
        switch placement {
        case .menuBar:
            #expect(placement.showsMenuBarIcon)
            #expect(placement.showsDockIcon == false)
        case .dock:
            #expect(placement.showsMenuBarIcon == false)
            #expect(placement.showsDockIcon)
        case .both:
            #expect(placement.showsMenuBarIcon)
            #expect(placement.showsDockIcon)
        }
    }

    @Test func exposesOnlyThreePlacements() {
        #expect(AppIconPlacement.allCases == [.menuBar, .dock, .both])
    }
}
