//
//  UIApplication+TopVC.swift
//

import UIKit

extension UIApplication {

    func topViewController(
        _ controller: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    ) -> UIViewController? {

        if let nav = controller as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }

        if let tab = controller as? UITabBarController {
            return topViewController(tab.selectedViewController)
        }

        if let presented = controller?.presentedViewController {
            return topViewController(presented)
        }

        return controller
    }
}
