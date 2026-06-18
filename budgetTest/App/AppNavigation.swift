import SwiftUI
import Combine

@MainActor
final class AppNavigation: ObservableObject {

    @Published var selectedTab = 0

    @Published var expandChecking = false
    @Published var expandSavings = false

    @Published var expandCredit = false
    @Published var expandLoans = false
}
