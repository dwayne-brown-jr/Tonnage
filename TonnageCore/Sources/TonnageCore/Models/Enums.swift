import Foundation

/// What kind of day a logged session represents. Drives the TRAIN day-type toggle.
public enum DayType: String, Codable, CaseIterable, Sendable, Identifiable {
    case lift
    case activeRest
    case fullRest

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lift:       "Lift"
        case .activeRest: "Active Rest"
        case .fullRest:   "Full Rest"
        }
    }

    public var systemImage: String {
        switch self {
        case .lift:       "dumbbell.fill"
        case .activeRest: "figure.walk"
        case .fullRest:   "bed.double.fill"
        }
    }
}

/// The five-week block progression. Source of truth for week labels + intent text.
public enum WeekPhase: String, Codable, CaseIterable, Sendable, Identifiable {
    case ramp    // W1
    case build   // W2
    case push    // W3
    case peak    // W4
    case deload  // W5

    public var id: String { rawValue }

    public var weekNumber: Int {
        switch self {
        case .ramp:   1
        case .build:  2
        case .push:   3
        case .peak:   4
        case .deload: 5
        }
    }

    public var title: String { rawValue.uppercased() }

    public var detail: String {
        switch self {
        case .ramp:   "Leave an extra rep in reserve, trust the process"
        case .build:  "+5 lb on compounds if last week was clean"
        case .push:   "+5 lb again or +1 rep"
        case .peak:   "True top set on each compound, no grinders"
        case .deload: "2 sets, ~60% load, leave 4–5 in reserve"
        }
    }

    /// Maps a 1-based week number to its phase, clamped to the 5-week block.
    public static func forWeek(_ week: Int) -> WeekPhase {
        switch max(1, min(5, week)) {
        case 1:  .ramp
        case 2:  .build
        case 3:  .push
        case 4:  .peak
        default: .deload
        }
    }
}

/// Quick-add categories for the MOVE tab. Each maps to an SF Symbol and (later)
/// an HKWorkoutActivityType.
public enum ActivityKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case walk
    case weightedVestWalk
    case stadiumStairs
    case stairMaster
    case bike
    case sport
    case mobility
    case recovery
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .walk:             "Walk"
        case .weightedVestWalk:  "Weighted Vest Walk"
        case .stadiumStairs:     "Stadium Stairs"
        case .stairMaster:       "Stair Master"
        case .bike:              "Bike"
        case .sport:             "Sport"
        case .mobility:          "Mobility"
        case .recovery:          "Recovery"
        case .custom:            "Custom"
        }
    }

    public var systemImage: String {
        switch self {
        case .walk:             "figure.walk"
        case .weightedVestWalk:  "figure.walk.motion"
        case .stadiumStairs:     "figure.stairs"
        case .stairMaster:       "figure.stair.stepper"
        case .bike:              "figure.outdoor.cycle"
        case .sport:             "figure.run"
        case .mobility:          "figure.cooldown"
        case .recovery:          "bed.double.fill"
        case .custom:            "plus.circle.fill"
        }
    }
}
