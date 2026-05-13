import SwiftUI

/// A ScrollView anchored to the bottom: content grows upward and the view
/// starts scrolled to the bottom. Short lists are bottom-aligned within the
/// available space.
///
/// ## Scrolling to the bottom
///
/// Two triggers are available and can be used independently or together:
///
/// - `scrollToBottomTrigger`: increment an `Int` to fire a one-shot jump,
///   e.g. immediately after appending a new item.
///
/// - `scrollToBottomOnChange`: an `AnyHashable` token whose *identity* drives
///   the scroll. When its value changes the view scrolls to the bottom after
///   a one-actor-turn defer so layout can settle with the new content size.
///   Pass a value that changes when the content *set* changes but stays equal
///   when the content is merely re-sorted — e.g. `AnyHashable(Set(ids))`.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
    var scrollToBottomOnChange: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            content()
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // .sizeChanges intentionally omitted: on iOS 26 it fires inside the layout pass
        // with the ambient (animated) transaction, producing a visible spring scroll.
        // All content-change cases are handled explicitly by the two onChange triggers
        // below, both of which use withAnimation(.none).
        .scrollPosition($scrollPosition)
        .onChange(of: scrollToBottomTrigger) { _, _ in
            // withAnimation(.none) suppresses the animated transaction that onChange
            // passes to ScrollPosition.scrollTo on iOS 26+. Without this, scrollTo
            // inherits the ambient animation and produces a visible slide.
            withAnimation(.none) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: scrollToBottomOnChange) { _, _ in
            // Defer one actor turn so layout settles with the new content
            // size before scrolling (filter-expand / content-swap path).
            Task { @MainActor in
                withAnimation(.none) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }
}
