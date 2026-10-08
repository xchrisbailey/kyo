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
}
