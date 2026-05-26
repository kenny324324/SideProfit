//
//  InAppBrowser.swift
//  DevCal
//
//  Keeps every http/https tap inside the app via SFSafariViewController so
//  users never bounce to Safari for legal pages, help docs, or any future
//  link. Attach once at the root with `.inAppBrowser()` — anything that
//  routes through SwiftUI's `OpenURLAction` (Link, AttributedString.link,
//  explicit @Environment(\.openURL) calls) is rerouted to an in-app sheet.
//  Non-web schemes (mailto:, tel:, custom) fall through to the system.
//

import SwiftUI
import SafariServices

extension View {
    func inAppBrowser() -> some View {
        modifier(InAppBrowserModifier())
    }
}

private struct InAppBrowserModifier: ViewModifier {
    @State private var presented: WebLink?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else {
                    return .systemAction
                }
                presented = WebLink(url: url)
                return .handled
            })
            .sheet(item: $presented) { link in
                SafariView(url: link.url)
                    .ignoresSafeArea()
            }
    }
}

private struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
