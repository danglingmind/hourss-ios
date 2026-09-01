import SwiftUI
import UIKit

/// Restores the edge-swipe back gesture.
///
/// Every detail screen in the app draws its own header, which means
/// `navigationBarBackButtonHidden(true)` — and UIKit switches off the interactive
/// pop gesture whenever the back button is hidden. That is reasonable for a screen
/// with no way back, but ours all have one, so the gesture should stay.
///
/// The recogniser belongs to the `UINavigationController`, so installing this once
/// at the root of a `NavigationStack` covers everything pushed onto it.
struct SwipeBackEnabler: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        Proxy(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Stands in for the delegate UIKit removes. Returning `false` at the root
    /// stack matters: without it the gesture fires with nothing to pop and leaves
    /// the navigation controller wedged.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    /// A zero-size controller whose only job is to reach the enclosing navigation
    /// controller. `UIViewController.navigationController` walks the parent chain,
    /// so it finds the one SwiftUI created.
    final class Proxy: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableSwipeBack()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        private func enableSwipeBack() {
            guard let navigationController else { return }
            coordinator.navigationController = navigationController
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = coordinator
        }
    }
}

extension View {
    /// Apply at the root of a `NavigationStack` to keep edge-swipe working on every
    /// screen it pushes, including those with a custom back control.
    func enablesSwipeBack() -> some View {
        background(SwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
