import SwiftUI

struct AppTabBar: View {
    @State private var selectedTab: Tab = .record
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var journalState: JournalState
    @EnvironmentObject var insightState: InsightState

    enum Tab: String, CaseIterable {
        case record = "Record"
        case history = "History"
        case insights = "Insights"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .record: return "mic.fill"
            case .history: return "clock.fill"
            case .insights: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView()
                .tabItem { Label(Tab.record.rawValue, systemImage: Tab.record.icon) }
                .tag(Tab.record)

            HistoryView()
                .tabItem { Label(Tab.history.rawValue, systemImage: Tab.history.icon) }
                .tag(Tab.history)

            InsightsView()
                .tabItem { Label(Tab.insights.rawValue, systemImage: Tab.insights.icon) }
                .tag(Tab.insights)

            SettingsView()
                .tabItem { Label(Tab.settings.rawValue, systemImage: Tab.settings.icon) }
                .tag(Tab.settings)
        }
        .tint(.accentVoice)
    }
}
