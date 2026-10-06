import SwiftUI
import UIKit

/// A **Memo**'s share payload made ready for the system share sheet: its text, then each photo
/// as a file holding the stored HEIC, so the receiving app gets the stored copy rather than a
/// re-encoded image. The files live in a temporary folder that `cleanUp()` removes.
///
/// This uses `UIActivityViewController` rather than `ShareLink`. `ShareLink` takes one `Transferable`
/// type per share, and a `Transferable`'s representations are fixed for the type, so a share of text
/// plus several images needs a wrapper that can't vary its content type per item. It also wants its
/// items before the card opens, which would read every photo's bytes up front.
final class MemoShareItems: Identifiable {
    let id = UUID()
    /// The text first, when there is any, then the photo files in order.
    let activityItems: [Any]
    private var folder: URL?

    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("memo-share", isDirectory: true)
    }

    /// `nil` when the payload has nothing to share.
    init?(_ payload: MemoSharePayload) {
        guard !payload.isEmpty else { return nil }
        // Anything a previous share left behind (the app was suspended before it finished).
        try? FileManager.default.removeItem(at: Self.root)

        var items: [Any] = []
        if let text = payload.text { items.append(text) }

        var folder: URL?
        if !payload.photos.isEmpty {
            let directory = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
                folder = directory
                for (index, data) in payload.photos.enumerated() {
                    let file = directory.appendingPathComponent("Photo \(index + 1).heic")
                    if (try? data.write(to: file)) != nil { items.append(file) }
                }
            }
        }
        guard !items.isEmpty else { return nil }
        self.activityItems = items
        self.folder = folder
    }

    /// Removes the photo files. Safe to call more than once.
    func cleanUp() {
        guard let folder else { return }
        self.folder = nil
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The iOS share sheet for a memo. `onFinish` runs when the sheet is done, shared or cancelled.
///
/// The activity controller's completion handler doesn't run when SwiftUI dismisses the sheet or
/// popover itself (a swipe down on iPhone, a tap outside the popover on iPad), so the files are
/// also removed when the sheet's view controller is torn down. That happens only once the sheet
/// is gone, never while a share destination is presented on top of it.
struct MemoShareSheet: UIViewControllerRepresentable {
    let items: MemoShareItems
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items.activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            items.cleanUp()
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        coordinator.items.cleanUp()
    }

    final class Coordinator {
        let items: MemoShareItems

        init(items: MemoShareItems) { self.items = items }
    }
}
