import Testing
@testable import TonnageCore

@Suite("Split presets")
struct SplitPresetTests {

    @Test("Each preset's session count matches its advertised days/week")
    func dayCounts() {
        #expect(SplitPreset.fullBody.makeSessions().count == 3)
        #expect(SplitPreset.upperLower.makeSessions().count == 4)
        #expect(SplitPreset.pushPullLegs.makeSessions().count == 6)
        for preset in SplitPreset.allCases {
            #expect(preset.makeSessions().count == preset.daysPerWeek)
        }
    }

    @Test("Every session leads with a compound (the top-set anchor) and has accessories")
    func compoundFirst() {
        for preset in SplitPreset.allCases {
            for session in preset.makeSessions() {
                let ex = session.orderedExercises
                #expect(ex.count >= 4, "\(preset.label) / \(session.name) too thin")
                #expect(ex.first?.isCompound == true, "\(preset.label) / \(session.name) should open on a compound")
            }
        }
    }

    @Test("sessionSpecs mirror the built sessions' names and focuses")
    func specsMatch() {
        for preset in SplitPreset.allCases {
            let built = preset.makeSessions()
            let specs = preset.sessionSpecs
            #expect(specs.map(\.name) == built.map(\.name))
            #expect(specs.map(\.focus) == built.map(\.subtitle))
        }
    }

    @Test("SeedProgram still produces the Upper/Lower default")
    func seedDefaultsToUpperLower() {
        #expect(SeedProgram.makeSessions().map(\.name) == SplitPreset.upperLower.makeSessions().map(\.name))
        #expect(SeedProgram.makeSessions().map(\.name) == ["Upper A", "Lower A", "Upper B", "Lower B"])
    }

    @Test("Every exercise in every preset has directions in the library")
    func allExercisesHaveDirections() {
        for preset in SplitPreset.allCases {
            for session in preset.makeSessions() {
                for ex in session.orderedExercises {
                    #expect(ExerciseLibrary.directions(for: ex.name) != nil,
                            "\(preset.label) / \(session.name): no directions for \(ex.name)")
                }
            }
        }
    }

    @Test("Sort orders are sequential within each session set")
    func sortOrders() {
        for preset in SplitPreset.allCases {
            let orders = preset.makeSessions().map(\.sortOrder)
            #expect(orders == Array(0..<orders.count))
        }
    }
}
