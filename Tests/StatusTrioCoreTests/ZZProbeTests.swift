import AppKit
import SwiftUI
import Testing
@testable import StatusTrioCore

@MainActor
final class ToggleModel: ObservableObject { @Published var detail = false }

@MainActor
private final class Rec: @unchecked Sendable { var e: [String] = [] }

private struct Root: View {
    @ObservedObject var model: ToggleModel
    let rec: Rec
    var body: some View {
        Group {
            if model.detail {
                Text("detail").id("detail")
                    .onAppear { rec.e.append("detail.appear") }
                    .onDisappear { rec.e.append("detail.disappear") }
            } else {
                Text("summary").id("summary")
                    .task(id: "same-id") { rec.e.append("summary.task") }
                    .onAppear { rec.e.append("summary.appear") }
                    .onDisappear { rec.e.append("summary.disappear") }
            }
        }
    }
}

@MainActor
struct ZZProbeTests {
    @Test func probeReturnPath() async throws {
        let rec = Rec()
        let model = ToggleModel()
        let hosting = NSHostingView(rootView: Root(model: model, rec: rec))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        print("PROBE A (summary): \(rec.e)")
        model.detail = true
        try? await Task.sleep(for: .milliseconds(300))
        print("PROBE B (detail):  \(rec.e)")
        model.detail = false
        try? await Task.sleep(for: .milliseconds(300))
        print("PROBE C (back):    \(rec.e)")
    }
}
