import Foundation
import SwiftData

/// An active-rest / cardio entry (the MOVE tab).
@Model
public final class Activity {
    public var name: String = ""
    public var kind: ActivityKind = ActivityKind.walk
    public var durationMinutes: Int = 0
    public var distanceMiles: Double?
    public var flights: Int?
    public var detail: String = ""
    public var date: Date = Date.now

    public init(
        name: String,
        kind: ActivityKind,
        durationMinutes: Int,
        distanceMiles: Double? = nil,
        flights: Int? = nil,
        detail: String = "",
        date: Date = .now
    ) {
        self.name = name
        self.kind = kind
        self.durationMinutes = durationMinutes
        self.distanceMiles = distanceMiles
        self.flights = flights
        self.detail = detail
        self.date = date
    }
}
