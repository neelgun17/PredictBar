import SwiftUI

/// One watched market: title (links to kalshi.com), current price vs target,
/// HIT badge once the target has been reached, and a remove button on hover.
struct WatchlistRowView: View {
    let item: WatchlistItem
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isTitleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if isTitleHovered {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .onHover { isTitleHovered = $0 }
                    .onTapGesture {
                        safeOpenKalshi(item.marketUrl)
                    }
                    .animation(.easeInOut(duration: 0.15), value: isTitleHovered)

                    HStack(spacing: 4) {
                        if item.isClosed {
                            Text("Closed")
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.65))
                        } else if let price = item.currentYesCents {
                            Text("\(price)¢")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundColor(.primary.opacity(0.65))
                        } else {
                            Text("—")
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.65))
                        }

                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.4))

                        Button(action: onEdit) {
                            Text("Target \(item.direction.symbol) \(item.targetCents)¢")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Edit target")
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }

                Spacer(minLength: 6)

                if item.lastHitAt != nil {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                        Text("HIT")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(3)
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.3))
                }
                .buttonStyle(.plain)
                .help("Remove from watchlist")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Edit Target...") { onEdit() }
                Button("Remove") { onRemove() }
            }

            Divider()
                .padding(.leading, 38) // Indent divider to match text
                .opacity(0.12)
        }
    }
}
