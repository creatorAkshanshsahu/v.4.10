import SwiftUI

@main
struct AKTVApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                LiveView()
                    .tabItem { Label("Live TV", systemImage: "tv") }
                MoviesView(kind: .movie)
                    .tabItem { Label("Movies", systemImage: "film") }
                MoviesView(kind: .series)
                    .tabItem { Label("Series", systemImage: "rectangle.stack") }
            }
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.31, green: 0.85, blue: 1.0))
        }
    }
}
