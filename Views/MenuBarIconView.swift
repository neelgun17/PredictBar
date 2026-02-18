import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        // Using Label is often more reliable for system menu bar styling
        HStack(spacing: 4) {
            Image(systemName: "chart.pie")
            if !viewModel.menuBarText.isEmpty {
                Text(viewModel.menuBarText)
                    .monospacedDigit()
            }
        }
    }
}
