import SwiftUI

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    let openSettings: () -> Void

    /// Height of the dictionary pane while it is being dragged; committed to
    /// the settings when the drag ends.
    @State private var dictionaryHeight: CGFloat
    /// Whether the card is part of the layout. It stays true until the
    /// slide-out finishes, so the card leaves with an animation.
    @State private var isCardShown = false
    /// The entry the card showed last, so a card sliding out keeps its content
    /// instead of emptying as soon as the model drops the entry.
    @State private var lastCard: CardSnapshot?

    private static let cardAnimation = Animation.smooth(duration: 0.25)

    init(model: TranslatorModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        _dictionaryHeight = State(initialValue: model.dictionaryPaneHeight)
        // A card that already has an entry when the view is built is part of
        // the first layout, not something that appeared while the user watched.
        _isCardShown = State(initialValue: model.isDictionaryVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            content
        }
        .background(
            ZStack {
                PanelBackground()
                Color(nsColor: .windowBackgroundColor).opacity(0.55)
            }
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
        .frame(minWidth: 520, minHeight: 260)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var header: some View {
        HStack(spacing: 2) {
            LanguageMenu(
                title: model.sourceLanguage.nativeName,
                options: Language.sourceOptions,
                selection: model.sourceCode,
                onSelect: model.selectSource
            )

            Button(action: model.swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canSwapLanguages ? Color.secondary : Color.secondary.opacity(0.35))
            .disabled(!model.canSwapLanguages)
            .help(model.canSwapLanguages ? "Swap languages" : "Select a source language to swap")

            LanguageMenu(
                title: model.targetLanguage.nativeName,
                options: Language.all,
                selection: model.targetCode,
                onSelect: model.selectTarget
            )

            Spacer(minLength: 8)

            if model.isTranslating {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)

                ActionButton(
                    systemName: "stop.fill",
                    title: "Stop",
                    help: "Stop translating",
                    action: model.stopTranslation
                )
                .transition(.opacity)
            } else if model.isOutputCurrent {
                ActionButton(
                    systemName: "xmark",
                    title: "Clear",
                    help: "Clear the source and translation",
                    action: model.clear
                )
            } else if !model.isSourceEmpty {
                ActionButton(
                    systemName: "arrow.right",
                    title: "Translate",
                    help: "Translate the edited text",
                    action: model.translateNow
                )
            }

            IconButton(
                systemName: model.copied ? "checkmark" : "square.on.square",
                help: "Copy translation",
                isEnabled: model.canCopy,
                action: model.copyOutput
            )

            IconButton(
                systemName: "gearshape",
                help: "Settings",
                action: openSettings
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(WindowDragArea())
        .animation(.easeInOut(duration: 0.15), value: model.isTranslating)
    }

    private var content: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                columns
                if isCardShown {
                    dictionaryPane(available: proxy.size.height)
                        .transition(.move(edge: .bottom))
                }
            }
            // The card slides up from under the panel and leaves the same way,
            // so it is clipped at the content bounds while it moves.
            .clipped()
        }
        .onChange(of: model.dictionaryState, initial: true) { _, state in
            guard case let .entry(entry) = state else { return }
            lastCard = CardSnapshot(entry: entry, sourceText: model.input)
        }
        .onChange(of: model.isDictionaryVisible, initial: true) { _, visible in
            guard visible != isCardShown else { return }
            withAnimation(Self.cardAnimation) { isCardShown = visible }
        }
    }

    /// The entry the card shows, falling back to the last one while the card
    /// slides out.
    private var cardState: DictionaryState {
        if case let .entry(entry) = model.dictionaryState { return .entry(entry) }
        return lastCard.map { .entry($0.entry) } ?? .none
    }

    private var cardSourceText: String {
        if case .entry = model.dictionaryState { return model.input }
        return lastCard?.sourceText ?? model.input
    }

    private func dictionaryPane(available: CGFloat) -> some View {
        VStack(spacing: 0) {
            DictionaryResizeHandle(
                displayedHeight: paneHeight(available: available),
                available: available,
                onDrag: { height in
                    dictionaryHeight = DictionaryPaneLayout.height(height, available: available)
                },
                onEnd: { height in
                    dictionaryHeight = DictionaryPaneLayout.height(height, available: available)
                    model.dictionaryPaneHeight = dictionaryHeight
                }
            )
            .frame(height: DictionaryPaneLayout.dividerHeight)
            DictionaryView(state: cardState, sourceText: cardSourceText)
                .frame(height: paneHeight(available: available))
        }
    }

    private func paneHeight(available: CGFloat) -> CGFloat {
        DictionaryPaneLayout.height(dictionaryHeight, available: available)
    }

    private var columns: some View {
        BilingualTextView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    status
                        .frame(width: max(proxy.size.width / 2 - BilingualScrollView.gutter * 2, 0), alignment: .topLeading)
                        .offset(x: (proxy.size.width / 2).rounded(.down) + BilingualScrollView.gutter, y: BilingualScrollView.topPadding)
                }
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var status: some View {
        if let message = model.errorMessage, !message.isEmpty {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } else if model.isTranslating, model.segments.isEmpty {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Translating…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}

/// Entry the dictionary card last displayed, captured with the source text it
/// was looked up for.
private struct CardSnapshot {
    var entry: DictionaryEntry
    var sourceText: String
}

/// Divider between the columns and the dictionary pane. It has to be an
/// AppKit view: the panel can be moved by dragging its background, so a
/// SwiftUI drag gesture would never see the mouse down. This view declines the
/// window drag and runs the resize itself.
private struct DictionaryResizeHandle: NSViewRepresentable {
    /// Height the pane shows right now, which may differ from the stored one
    /// when the window is too small.
    let displayedHeight: CGFloat
    /// Content height of the panel, the bound the drag is clamped against.
    let available: CGFloat
    let onDrag: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> DictionaryResizeView {
        let view = DictionaryResizeView()
        view.toolTip = "Drag to resize the dictionary"
        return view
    }

    func updateNSView(_ view: DictionaryResizeView, context: Context) {
        view.displayedHeight = displayedHeight
        view.available = available
        view.onDrag = onDrag
        view.onEnd = onEnd
    }
}

final class DictionaryResizeView: NSView {
    var displayedHeight: CGFloat = 0
    var available: CGFloat = 0
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat) -> Void)?

    private var dragStart: (height: CGFloat, windowY: CGFloat)?
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    /// The panel moves when its background is dragged; this view takes the
    /// drag for itself instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override var isFlipped: Bool { true }

    /// A click meant for the handle must start the drag even when the panel is
    /// not key yet.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = (displayedHeight, event.locationInWindow.y)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        onDrag?(height(for: event, from: dragStart))
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        self.dragStart = nil
        needsDisplay = true
        onEnd?(height(for: event, from: dragStart))
    }

    /// Dragging up grows the pane: the window y axis points up, the pane
    /// height is measured downwards.
    private func height(for event: NSEvent, from dragStart: (height: CGFloat, windowY: CGFloat)) -> CGFloat {
        let translation = dragStart.windowY - event.locationInWindow.y
        return DictionaryPaneLayout.draggedHeight(
            start: dragStart.height,
            translation: translation,
            available: available
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let isActive = isHovering || dragStart != nil
        let thickness: CGFloat = isActive ? 2 : 1
        let line = NSRect(
            x: 0,
            y: ((bounds.height - thickness) / 2).rounded(.down),
            width: bounds.width,
            height: thickness
        )
        NSColor.labelColor.withAlphaComponent(isActive ? 0.18 : 0.07).setFill()
        line.fill()
    }
}

private struct ActionButton: View {
    let systemName: String
    let title: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(isHovering ? 0.11 : 0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovering && isEnabled ? 0.07 : 0))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.35))
        .disabled(!isEnabled)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

struct LanguageMenu: View {
    let title: String
    let options: [Language]
    let selection: String
    let onSelect: (String) -> Void

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.45)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            LanguageList(options: options, selection: selection) { code in
                isPresented = false
                onSelect(code)
            }
        }
    }
}

struct LanguageList: View {
    let options: [Language]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(options) { language in
                    LanguageRow(
                        language: language,
                        isSelected: language.code == selection,
                        action: { onSelect(language.code) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 208, height: 320)
    }
}

private struct LanguageRow: View {
    let language: Language
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(language.nativeName)
                    .font(.system(size: 13))
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// An empty header area that moves the window when dragged. SwiftUI controls
/// keep their own clicks; this fills the free space between them and starts a
/// window drag directly, which works for the non-activating panel too.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView {
        WindowDragView()
    }

    func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
