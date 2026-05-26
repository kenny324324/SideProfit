//
//  RootView.swift
//  DevCal
//
//  Routes between the Auth screen and the main tab shell based on AuthService state.
//  Sign-in / sign-out / delete-account crossfade the same way Splash → home
//  does on cold launch (opacity, easeInOut, 0.5s) so the auth handoff feels
//  continuous instead of a hard cut.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            if auth.isSignedIn {
                MainTabView()
                    .transition(.opacity)
            } else {
                AuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: SplashDefaults.fadeOutDuration),
                   value: auth.isSignedIn)
        .font(Typography.font(.body))
        .tint(Theme.brand)
    }
}
