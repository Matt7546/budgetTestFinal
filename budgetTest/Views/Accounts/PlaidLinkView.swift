//
//  PlaidLinkView.swift
//

import SwiftUI
import LinkKit

struct PlaidLinkView: UIViewControllerRepresentable {
    let handler: Handler

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()

        DispatchQueue.main.async {
            handler.open(presentUsing: .viewController(controller))
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
