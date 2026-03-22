import SwiftUI

/// A ScrollView anchored to the bottom: content grows upward and the view
/// starts scrolled to the bottom. The minimum content height fills the available
/// space so short lists remain bottom-aligned rather than top-aligned.
///
/// Use `scrollToBottomTrigger` (increment an Int state) to programmatically
/// jump to the bottom — e.g. after adding a new item.
///
/// Unlike pairing `defaultScrollAnchor(.bottom)` with a `scrollPosition(id:)`
/// binding, this component uses a single mechanism: the `defaultScrollAnchor`
/// keeps the view at the bottom when content grows, and an explicit
/// `ScrollViewReader.scrollTo` handles trigger-based jumps. There is no
/// auto-scroll on content change, which prevents unwanted snapping when the
/// list is merely re-sorted.
struct BottomAnchoredScrollView<Content: View>: View {
    var scrollToBottomTrigger: Int = 0
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
            }
        }
    }
}
