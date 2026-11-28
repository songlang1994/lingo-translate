import CoreGraphics

/// Geometry of the dictionary pane under the two columns. The pane is
/// user-resizable, but it never grows so tall that the columns lose their
/// last two text lines, and never shrinks below its own minimum.
enum DictionaryPaneLayout {
    /// Enough for a pronunciation row, one sense, and an example.
    static let minimumHeight: CGFloat = 96
    /// The drag handle doubles as the separator line.
    static let dividerHeight: CGFloat = 7
    /// Slack on top of the two lines, so a two-line text never sits exactly
    /// at the scroll view's edge where rounding could clip it.
    static let columnsHeadroom: CGFloat = 6
    /// Two text lines plus the columns' padding, so a source or translation
    /// of up to two lines stays fully visible without scrolling while the
    /// dictionary pane is open.
    static var minimumColumnsHeight: CGFloat {
        BilingualScrollView.topPadding
            + SegmentTextView.lineHeight * 2
            + BilingualScrollView.bottomPadding
            + columnsHeadroom
    }

    static func limits(available: CGFloat) -> ClosedRange<CGFloat> {
        minimumHeight...max(minimumHeight, available - dividerHeight - minimumColumnsHeight)
    }

    /// Clamps a proposed pane height to the bounds the current window allows.
    static func height(_ proposed: CGFloat, available: CGFloat) -> CGFloat {
        min(max(proposed, minimumHeight), limits(available: available).upperBound)
    }

    /// Height during a divider drag: dragging up (`negative` translation) grows
    /// the pane, and the result is clamped to the current window.
    static func draggedHeight(start: CGFloat, translation: CGFloat, available: CGFloat) -> CGFloat {
        height(start - translation, available: available)
    }
}
