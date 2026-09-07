import SwiftUI
import MessageUI
import UIKit

/// In-app mail composer for beta feedback, pre-filled with recipient, subject, and a footer
/// carrying the app version/build + device so reports arrive with the context you need.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

/// Beta-feedback recipient + the pre-filled message context.
enum Feedback {
    static let recipient = "dwaynebrown2012@gmail.com"
    static let subject = "Tonnage Beta Feedback"

    static var body: String {
        let info = Bundle.main.infoDictionary
        let v = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (info?["CFBundleVersion"] as? String) ?? "?"
        let device = UIDevice.current
        return """


        ——————
        Tonnage v\(v) (\(b))
        \(device.model) · iOS \(device.systemVersion)
        (Screenshots welcome!)
        """
    }

    /// mailto: fallback for when no Mail account is configured.
    static var mailtoURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = recipient
        c.queryItems = [.init(name: "subject", value: subject), .init(name: "body", value: body)]
        return c.url
    }
}
