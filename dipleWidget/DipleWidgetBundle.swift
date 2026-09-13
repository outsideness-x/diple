import SwiftUI
import WidgetKit

@main
struct DipleWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyPassageWidget()
        NotesWidget()
        #if !targetEnvironment(macCatalyst)
        NewNoteControl()
        #endif
    }
}
