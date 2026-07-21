import Foundation
import SwiftData

@Model
final class DayCompletion {
    @Attribute(.unique) var dateKey: String
    var completedHours: Double

    init(dateKey: String, completedHours: Double) {
        self.dateKey = dateKey
        self.completedHours = completedHours
    }
}
