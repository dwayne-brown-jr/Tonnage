import Testing
import Foundation
@testable import TonnageCore

@Suite("Body metrics")
struct BodyMetricsTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_700_000_000))!
    }

    @Test("latest returns the most recent value per type with delta from the prior entry")
    func latestWithDelta() {
        let m = [
            BodyMeasurement(type: .waist, value: 34, date: day(0)),
            BodyMeasurement(type: .waist, value: 33, date: day(7)),
            BodyMeasurement(type: .arm,   value: 15, date: day(0)),
        ]
        let latest = BodyMetrics.latest(m)
        let waist = latest.first { $0.type == .waist }
        let arm = latest.first { $0.type == .arm }

        #expect(waist?.value == 33)
        #expect(waist?.delta == -1)          // 33 − 34
        #expect(arm?.value == 15)
        #expect(arm?.delta == nil)           // only one entry
    }

    @Test("latest is ordered by canonical MeasurementType order")
    func latestOrdered() {
        let m = [
            BodyMeasurement(type: .calf, value: 16, date: day(0)),
            BodyMeasurement(type: .chest, value: 42, date: day(0)),
        ]
        let order = BodyMetrics.latest(m).map(\.type)
        #expect(order == [.chest, .calf])   // chest precedes calf in allCases
    }

    @Test("series for a type is time-ordered ascending")
    func seriesOrdered() {
        let m = [
            BodyMeasurement(type: .waist, value: 33, date: day(7)),
            BodyMeasurement(type: .waist, value: 34, date: day(0)),
            BodyMeasurement(type: .arm,   value: 15, date: day(3)),
        ]
        let series = BodyMetrics.series(of: .waist, in: m)
        #expect(series.map(\.value) == [34, 33])
        #expect(series.first!.date < series.last!.date)
    }

    @Test("trackedTypes returns only present types, in canonical order")
    func trackedTypes() {
        let m = [
            BodyMeasurement(type: .calf, value: 16, date: day(0)),
            BodyMeasurement(type: .waist, value: 33, date: day(0)),
        ]
        #expect(BodyMetrics.trackedTypes(in: m) == [.waist, .calf])
        #expect(BodyMetrics.trackedTypes(in: []).isEmpty)
    }

    @Test("lowerIsBetter flags waist and body fat only")
    func lowerIsBetter() {
        #expect(MeasurementType.waist.lowerIsBetter)
        #expect(MeasurementType.bodyFat.lowerIsBetter)
        #expect(!MeasurementType.arm.lowerIsBetter)
        #expect(!MeasurementType.chest.lowerIsBetter)
    }
}
