import Testing
@testable import TonnageCore

@Suite("Plate math")
struct PlateMathTests {

    @Test("225 on a 45 bar = two 45s per side")
    func twoFortyFives() {
        let l = PlateMath.loadout(target: 225, bar: 45)
        #expect(l.perSide == [.init(plate: 45, perSide: 2)])
        #expect(l.achievable == 225)
        #expect(l.isExact)
    }

    @Test("Mixed plates: 100 = 25 + 2.5 per side")
    func mixed() {
        let l = PlateMath.loadout(target: 100, bar: 45)
        #expect(l.perSide == [.init(plate: 25, perSide: 1), .init(plate: 2.5, perSide: 1)])
        #expect(l.achievable == 100)
        #expect(l.isExact)
    }

    @Test("Empty bar needs no plates")
    func barOnly() {
        let l = PlateMath.loadout(target: 45, bar: 45)
        #expect(l.perSide.isEmpty)
        #expect(l.achievable == 45)
    }

    @Test("Unreachable weight reports the closest below + remainder")
    func inexact() {
        let l = PlateMath.loadout(target: 96, bar: 45) // 25.5/side → 25, 0.5 short
        #expect(l.achievable == 95)
        #expect(!l.isExact)
        #expect(abs(l.remainderPerSide - 0.5) < 0.001)
    }
}
