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
            AppLogger.plaidOAuthDiagnostic("Plaid Link presentation started")
            handler.open(presentUsing: .viewController(controller))
            AppLogger.plaidOAuthDiagnostic("Plaid Link presentation call returned")
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
