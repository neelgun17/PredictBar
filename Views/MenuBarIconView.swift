import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        // Using Label is often more reliable for system menu bar styling
        Label {
            Text(String(format: "%.2f%%", viewModel.overallROI))
                .monospacedDigit() // Keeps width stable
        } icon: {
            Image(systemName: "chart.bar.fill")
        }
    }
}
