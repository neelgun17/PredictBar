import SwiftUI

private struct WatchlistContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Watchlist tab content: markets the user is watching for a price target.
struct WatchlistView: View {
    @ObservedObject var viewModel = WatchlistViewModel.shared
    @ObservedObject var settingsViewModel = SettingsViewModel.shared

    @State private var isAddPresented = false
    @State private var editingItem: WatchlistItem?

    private let listMaxHeight: CGFloat = 240
    @State private var contentHeight: CGFloat = 0
    private var overflows: Bool { contentHeight > listMaxHeight + 1 }

    private var canAdd: Bool {
        settingsViewModel.hasCredentials && !DashboardViewModel.isDemoMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WATCHLIST")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
                Spacer()
                Button(action: { isAddPresented = true }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(canAdd ? .accentColor : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .help(canAdd ? "Watch a market" : "Connect your Kalshi account to watch markets")
                .popover(isPresented: $isAddPresented) {
                    AddWatchlistItemView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !settingsViewModel.hasCredentials {
                emptyState(
                    icon: "key.horizontal",
                    title: "Connect your Kalshi account",
                    message: "Add your Kalshi API key to start watching markets."
                )
            } else if viewModel.items.isEmpty {
                emptyState(
                    icon: "eye",
                    title: "No Watched Markets",
                    message: "Paste a kalshi.com market URL or ticker to get alerted when the price hits your target."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.items) { item in
                            WatchlistRowView(
                                item: item,
                                onEdit: { editingItem = item },
                                onRemove: { viewModel.remove(id: item.id) }
                            )
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: WatchlistContentHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
                .frame(height: contentHeight == 0
                       ? listMaxHeight
                       : min(contentHeight, listMaxHeight))
                .onPreferenceChange(WatchlistContentHeightKey.self) { contentHeight = $0 }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: overflows ? 0.93 : 1),
                            .init(color: overflows ? .black.opacity(0) : .black, location: overflows ? 0.98 : 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .popover(item: $editingItem) { item in
            EditWatchTargetView(item: item)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if canAdd {
                Button("Watch a Market") { isAddPresented = true }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
