/// A test double for `ThemeIDTransport`: records every id published and lets a test deliver an id
/// to the registered receiver. Like the real transport it holds the latest delivered id and hands
/// it to a receiver registered later.
@MainActor
final class ControllableThemeTransport: ThemeIDTransport {
    private(set) var published: [String] = []
    private var handler: (@MainActor (String) -> Void)?
    private var latestDelivered: String?

    func publish(themeID: String) {
        published.append(themeID)
    }

    func setThemeIDHandler(_ handler: @escaping @MainActor (String) -> Void) {
        self.handler = handler
        if let latestDelivered {
            handler(latestDelivered)
        }
    }

    /// Delivers `themeID` as the phone's latest, to the receiver now or once one registers.
    func deliver(_ themeID: String) {
        latestDelivered = themeID
        handler?(themeID)
    }
}
