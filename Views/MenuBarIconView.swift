import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        // Using Label is often more reliable for system menu bar styling
        Label {
            Text(viewModel.overallROI, format: .percent.precision(.fractionLength(2)))
                .monospacedDigit() // Keeps width stable
        } icon: {
            Image(systemName: "chart.bar.fill")
        }
    }
}
