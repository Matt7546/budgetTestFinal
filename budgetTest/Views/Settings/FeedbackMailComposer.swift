import Foundation
import MessageUI
import SwiftUI
import UIKit

struct FeedbackMailDraft {

    let recipient: String
    let subject = "Caldera Feedback"
    let body: String

    init(
        recipient: String,
        appVersion: String,
        buildNumber: String
    ) {
        self.recipient = recipient
        self.body = Self.makeBody(
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }

    var mailtoURL: URL {
        Self.mailtoURL(
            recipient: recipient,
            subject: subject,
            body: body
        )
    }

    static func mailtoURL(
        recipient: String,
        subject: String,
        body: String? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]

        if let body {
            components.queryItems?.append(
                URLQueryItem(name: "body", value: body)
            )
        }

        return components.url ?? URL(string: "mailto:\(recipient)")!
    }

    private static func makeBody(
        appVersion: String,
        buildNumber: String
    ) -> String {
        let device = UIDevice.current

        return """
        Screen:
        What I was trying to do:
        What happened:
        What I expected:
        Screenshot attached?:

        Build: \(appVersion) (\(buildNumber))
        Device: \(device.model)
        iOS version: \(device.systemVersion)
        App mode: \(currentAppMode)
        """
    }

    private static var currentAppMode: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }
}

struct FeedbackMailComposer: UIViewControllerRepresentable {

    let draft: FeedbackMailDraft
    let onFinish: () -> Void

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([draft.recipient])
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        return composer
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {

        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish()
            }
        }
    }
}
