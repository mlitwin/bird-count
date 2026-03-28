import SwiftUI

/// A ScrollView anchored to the bottom: content grows upward and the view
/// starts scrolled to the bottom. The minimum content height fills the available
/// space so short lists remain bottom-aligned rather than top-aligned.
///
/// ## Scrolling to the bottom
///
/// Two triggers are available and can be used independently or together:
///
/// - `scrollToBottomTrigger`: increment an `Int` to fire a one-shot jump,
///   e.g. immediately after appending a new item.
///
/// - `scrollToBottomOnChange`: an `AnyHashable` token whose *identity* drives
///   the scroll. When its value changes the view scrolls to the bottom. Pass
///   a value that changes when the content *set* changes but stays equal when
///   the content is merely re-sorted — e.g. `AnyHashable(Set(ids))`.
///   This re-anchors the view after a filter/search resets the content without
///   snapping on every sort-order update.
///
/// ## Why not `defaultScrollAnchor` alone?
///
/// `defaultScrollAnchor(.bottom)` only sets the *initial* position; it does
/// not re-anchor when content size changes. If content shrinks (e.g. a filter
/// narrows the list) the scroll offset is clamped to the smaller range, and
/// when the content later expands that same low offset sits near the top of
/// the new large list. The explicit `scrollTo` calls handle this.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
    var scrollToBottomOnChange: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    private static var anchorID: String { "__bottom_anchor__" }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        content()
                        Color.clear
                            .frame(height: 1)
                            .id(Self.anchorID)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    reader.scrollTo(Self.anchorID, anchor: .bottom)
                }
                .onChange(of: scrollToBottomTrigger) { _, _ in
                    reader.scrollTo(Self.anchorID, anchor: .bottom)
                }
                .onChange(of: scrollToBottomOnChange) { _, _ in
                    reader.scrollTo(Self.anchorID, anchor: .bottom)
                }
            }
        }
    }
}
