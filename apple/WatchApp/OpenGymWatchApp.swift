import SwiftUI

@main
struct OpenGymWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
                .environment(\.locale, Locale(identifier: model.language))
                .environment(\.layoutDirection, model.language == "ar" ? .rightToLeft : .leftToRight)
        }
    }
}
