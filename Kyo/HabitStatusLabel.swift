import SwiftUI

/// A habit's week progress (weekly targets) then its streak flame, hidden at 0. The same on
/// Today's rows and the Habits sheet's. The caller sets the color and the accessibility.
struct HabitStatusLabel: View {
    let weekProgress: HabitWeekProgress?
    /// Days for day-based habits, weeks for weekly targets.
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            if let progress = weekProgress {
                Text("\(progress.count)/\(progress.target)")
                    .font(.subheadline.monospacedDigit())
                if streak >= 1 { Text("·") }
            }
            if streak >= 1 {
                Label {
                    Text(weekProgress == nil ? "\(streak)" : "\(streak)w")
                        .font(.subheadline.monospacedDigit())
                } icon: {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    /// What VoiceOver says for the week progress, such as "2 of 3 this week".
    static func spokenWeekProgress(_ progress: HabitWeekProgress) -> String {
        "\(progress.count) of \(progress.target) this week"
    }

    /// What VoiceOver says for a streak of 1 or more, such as "4 day streak" or "2 week streak".
    static func spokenStreak(_ streak: Int, isWeekly: Bool) -> String {
        "\(streak) \(isWeekly ? "week" : "day") streak"
    }
}
