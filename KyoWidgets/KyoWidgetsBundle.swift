import SwiftUI
import WidgetKit

@main
struct KyoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecordMemoControl()
        WriteMemoControl()
    }
}
