import AppKit

/// An overlay scroller that draws only its knob. The system scroller paints a
/// light track behind the knob while the scroller is visible, which reads as a
/// white strip against the panel's translucent background.
final class TracklessScroller: NSScroller {
    /// Overlay scrollers only accept a replacement scroller that says it
    /// supports them.
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}
