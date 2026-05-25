//
//  RootView.swift
//  DevCal
//
//  Routes between the Auth screen and the main tab shell based on AuthService state.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.snappy, value: auth.isSignedIn)
        .font(Typography.font(.body))
        .tint(Theme.brand)
    }
}
