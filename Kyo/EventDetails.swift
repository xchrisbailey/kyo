import UIKit

/// An event's details ready to show: the view controller to put in a sheet, for the occurrence
/// that was asked for.
struct PresentedEventDetail: Identifiable {
    let id: ScheduleEventID
    let viewController: UIViewController
}

/// Builds the screen that shows one event's details. The live implementation is the only code that
/// touches `EKEvent` and `EKEventViewController`; it runs on the main actor because the view
/// controller does. A `CalendarService` hands out its presenter, so the presenter shares the
/// service's store.
@MainActor
protocol EventDetailPresenter: Sendable {
    /// A view controller showing `id`'s details, or `nil` when that occurrence can't be found any
    /// more, for example because it was deleted since the Schedule was read. `onDone` is called
    /// when the user finishes with the screen, so the caller can dismiss it.
    func viewController(for id: ScheduleEventID, onDone: @escaping @MainActor () -> Void) -> UIViewController?
}
