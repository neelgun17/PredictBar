import SwiftUI

private struct OutcomeListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Add-to-watchlist popover: paste a kalshi.com URL or ticker, resolve it to a
/// market (with an outcome picker for multi-market events), then set the target.
struct AddWatchlistItemView: View {
    @ObservedObject var viewModel = WatchlistViewModel.shared
    @Environment(\.dismiss) var dismiss

    private enum Phase {
        case input
        case resolving
        case pickMarket([NetworkManager.Market])
        case configure(NetworkManager.Market)
    }

    @State private var phase: Phase = .input
    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var targetCents = 50
    @State private var direction: WatchlistItem.Direction = .atOrBelow

    private let outcomeListMaxHeight: CGFloat = 280
    @State private var outcomeListHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watch a Market")
                .font(.headline)

            switch phase {
            case .input, .resolving:
                inputView
            case .pickMarket(let markets):
                pickerView(markets)
            case .configure(let market):
                WatchTargetForm(
                    marketTitle: market.title,
                    subtitle: market.subtitle,
                    currentPriceCents: WatchlistItem.displayPriceCents(
                        lastPrice: market.lastPrice, yesBid: market.yesBid, yesAsk: market.yesAsk
                    ),
                    targetCents: $targetCents,
                    direction: $direction,
                    confirmLabel: "Watch"
                ) {
                    viewModel.watch(market: market, targetCents: targetCents, direction: direction)
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var isResolving: Bool {
        if case .resolving = phase { return true }
        return false
    }

    @ViewBuilder
    private var inputView: some View {
        TextField("Paste market URL or ticker", text: $inputText)
            .textFieldStyle(.roundedBorder)
            .disabled(isResolving)
            .onSubmit(resolve)

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)
        } else {
            Text("Get notified when the price reaches your target.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }

        HStack {
            Spacer()
            if isResolving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Next") { resolve() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func pickerView(_ markets: [NetworkManager.Market]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick an outcome")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(markets, id: \.ticker) { market in
                        Button(action: { select(market) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(market.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 4) {
                                    if let sub = market.subtitle, !sub.isEmpty {
                                        Text(sub)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    if let price = WatchlistItem.displayPriceCents(
                                        lastPrice: market.lastPrice, yesBid: market.yesBid, yesAsk: market.yesAsk
                                    ) {
                                        Text("\(price)¢")
                                            .font(.system(size: 10))
                                            .monospacedDigit()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.12)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: OutcomeListHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            // A bare maxHeight lets the popover collapse the list to a sliver;
            // measure the content and claim its real height up to the cap.
            .frame(height: outcomeListHeight == 0
                   ? outcomeListMaxHeight
                   : min(outcomeListHeight, outcomeListMaxHeight))
            .onPreferenceChange(OutcomeListHeightKey.self) { outcomeListHeight = $0 }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Back") {
                    errorMessage = nil
                    phase = .input
                }
            }
        }
    }

    private func resolve() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        errorMessage = nil
        phase = .resolving

        viewModel.resolve(input: query) { result in
            switch result {
            case .success(.market(let market)):
                prefill(for: market)
                phase = .configure(market)
            case .success(.candidates(let markets)):
                phase = .pickMarket(markets)
            case .failure(let error):
                errorMessage = error.errorDescription
                phase = .input
            }
        }
    }

    private func select(_ market: NetworkManager.Market) {
        switch viewModel.validated(market) {
        case .success(let market):
            errorMessage = nil
            prefill(for: market)
            phase = .configure(market)
        case .failure(let error):
            errorMessage = error.errorDescription
        }
    }

    private func prefill(for market: NetworkManager.Market) {
        if let price = WatchlistItem.displayPriceCents(
            lastPrice: market.lastPrice, yesBid: market.yesBid, yesAsk: market.yesAsk
        ) {
            targetCents = min(99, max(1, price))
        }
    }
}

/// Target price + direction form, shared by the add flow and the edit popover.
struct WatchTargetForm: View {
    let marketTitle: String
    let subtitle: String?
    let currentPriceCents: Int?
    @Binding var targetCents: Int
    @Binding var direction: WatchlistItem.Direction
    let confirmLabel: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(marketTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if let currentPriceCents {
                        Text("Yes @ \(currentPriceCents)¢")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }

            Picker("", selection: $direction) {
                ForEach(WatchlistItem.Direction.allCases, id: \.self) { dir in
                    Text("\(dir.label) \(dir.symbol)").tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("Target Price (¢)")
                    .frame(width: 100, alignment: .leading)
                TextField("50", value: $targetCents, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onChange(of: targetCents) { newValue in
                        targetCents = min(99, max(1, newValue))
                    }
            }

            Text("Notifies when the Yes price is \(direction.label.lowercased()) \(targetCents)¢.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))

            HStack {
                Spacer()
                Button(confirmLabel) { onConfirm() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Edit popover for an existing watchlist item's target.
struct EditWatchTargetView: View {
    let item: WatchlistItem
    @ObservedObject var viewModel = WatchlistViewModel.shared
    @Environment(\.dismiss) var dismiss

    @State private var targetCents: Int
    @State private var direction: WatchlistItem.Direction

    init(item: WatchlistItem) {
        self.item = item
        _targetCents = State(initialValue: item.targetCents)
        _direction = State(initialValue: item.direction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Watch Target")
                .font(.headline)

            WatchTargetForm(
                marketTitle: item.title,
                subtitle: item.subtitle,
                currentPriceCents: item.currentYesCents,
                targetCents: $targetCents,
                direction: $direction,
                confirmLabel: "Save"
            ) {
                viewModel.updateTarget(id: item.id, targetCents: targetCents, direction: direction)
                dismiss()
            }
        }
        .padding()
        .frame(width: 300)
    }
}
