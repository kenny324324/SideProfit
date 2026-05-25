//
//  MainTabView.swift
//  DevCal
//
//  The signed-in shell. Three tabs: Projects (the core flow), Insights
//  (cross-project analytics), and Settings.
//
//  Tab bar icons now come from PhosphorSymbols (custom SF Symbols built from
//  the Phosphor SVG set). They behave like Apple SF Symbols, so iOS's tab bar
//  surface renders them correctly.
//

import SwiftUI
import PhosphorSymbols

struct MainTabView: View {
    @State private var selection: Tab = .projects

    enum Tab: Hashable {
        case projects
        case insights
        case settings
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $selection) {
                SwiftUI.Tab(value: Tab.projects) {
                    NavigationStack { ProjectListView() }
                } label: {
                    Image(ph: "stack")
                        .accessibilityLabel("Projects")
                }

                SwiftUI.Tab(value: Tab.insights) {
                    NavigationStack { InsightsView() }
                } label: {
                    Image(ph: "chart-line-up")
                        .accessibilityLabel("Insights")
                }

                SwiftUI.Tab(value: Tab.settings) {
                    NavigationStack { SettingsView() }
                } label: {
                    Image(ph: "gear-six")
                        .accessibilityLabel("Settings")
                }
            }
        } else {
            TabView(selection: $selection) {
                NavigationStack {
                    ProjectListView()
                }
                .tabItem { Image(ph: "stack") }
                .tag(Tab.projects)

                NavigationStack {
                    InsightsView()
                }
                .tabItem { Image(ph: "chart-line-up") }
                .tag(Tab.insights)

                NavigationStack {
                    SettingsView()
                }
                .tabItem { Image(ph: "gear-six") }
                .tag(Tab.settings)
            }
        }
    }
}
