import SwiftUI
import UIKit

/// Presents the iOS share sheet for a **Task** while `payload` is set, anchored to the view it is
/// attached to as a background, so that on iPad the popover points at the Task's row. `payload` is
/// cleared when the sheet finishes, shared or cancelled.
///
/// This uses `UIActivityViewController` presented from UIKit rather than `ShareLink`, so that the
/// context menu and the VoiceOver action can open the same sheet, and so the sheet can be
/// anchored to the row on iPad.
struct TaskShareAnchor: UIViewRepresentable {
    @Binding var payload: TaskSharePayload?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let payload, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true
        let binding = $payload
        let coordinator = context.coordinator
        // The context menu is still dismissing when Share is chosen; wait a turn so UIKit will present.
        DispatchQueue.main.async { [weak view] in
            guard let view, let presenter = Self.presenter(for: view) else {
                coordinator.finish(clearing: binding)
                return
            }
            let controller = UIActivityViewController(activityItems: payload.activityItems, applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = view
            controller.popoverPresentationController?.sourceRect = view.bounds
            controller.completionWithItemsHandler = { _, _, _, _ in
                coordinator.finish(clearing: binding)
            }
            presenter.present(controller, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isPresenting = false

        func finish(clearing payload: Binding<TaskSharePayload?>) {
            isPresenting = false
            payload.wrappedValue = nil
        }
    }

    /// The topmost view controller over `view`'s window.
    private static func presenter(for view: UIView) -> UIViewController? {
        var controller = view.window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
