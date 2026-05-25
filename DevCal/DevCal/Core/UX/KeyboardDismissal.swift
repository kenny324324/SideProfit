//
//  KeyboardDismissal.swift
//  DevCal
//
//  Installs one window-level tap recognizer so tapping outside active inputs
//  dismisses the keyboard across the whole SwiftUI hierarchy, including sheets.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

extension View {
    func dismissKeyboardOnTapOutside() -> some View {
        modifier(KeyboardDismissOnTapOutsideModifier())
    }
}

private struct KeyboardDismissOnTapOutsideModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissGestureInstaller())
    }
}

private struct KeyboardDismissGestureInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.coordinator = context.coordinator
    }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator? {
            didSet {
                coordinator?.installerView = self
                installGestureIfNeeded()
            }
        }

        private weak var installedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installGestureIfNeeded()
        }

        deinit {
            if let recognizer = coordinator?.tapGestureRecognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
        }

        private func installGestureIfNeeded() {
            guard let coordinator, let window else { return }
            guard installedWindow !== window else { return }

            if let installedWindow {
                installedWindow.removeGestureRecognizer(coordinator.tapGestureRecognizer)
            }

            window.addGestureRecognizer(coordinator.tapGestureRecognizer)
            installedWindow = window
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var installerView: UIView?

        lazy var tapGestureRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            installerView?.window?.endEditing(true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.isInsideKeyboardDismissExcludedView
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isInsideKeyboardDismissExcludedView: Bool {
        if self is UITextInput || self is UIControl || self is UINavigationBar || self is UITabBar || self is UIToolbar {
            return true
        }

        return superview?.isInsideKeyboardDismissExcludedView ?? false
    }
}
#endif
