import SwiftUI

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    let openSettings: () -> Void

    @FocusState private var focusedParagraph: Int?

    @State private var metrics = ScrollMetrics()

    private static let panelSpace = "lingo-panel"

    private let rowSpacing: CGFloat = 12
    private let gutter: CGFloat = 14
    private let bottomPadding: CGFloat = 14

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
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
        .frame(minWidth: 520, minHeight: 260)
        .ignoresSafeArea(.container, edges: .top)
        .coordinateSpace(.named(Self.panelSpace))
        .background(MouseDownMonitor { point in
            handleClick(at: point)
        })
        .onPreferenceChange(RowFramePreferenceKey.self) { frames in
            metrics.rowFrames = frames
        }
        .onPreferenceChange(ViewportFramePreferenceKey.self) { frame in
            metrics.viewportFrame = frame
        }
        .onChange(of: model.input) { _, _ in
            model.inputDidChange()
        }
        .onChange(of: model.focusToken) { _, _ in
            focusInput()
        }
        .onAppear {
            focusInput()
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            LanguageMenu(
                title: model.sourceLanguage.name,
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
            .foregroundStyle(.tertiary)
            .help("Swap languages")

            LanguageMenu(
                title: model.targetLanguage.name,
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

                StopButton(action: model.stopTranslation)
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.15), value: model.isTranslating)
    }

    private var content: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    row(index)
                }
            }
            .padding(.bottom, bottomPadding)
            .background(
                ScrollFollowObserver(isTranslating: model.isTranslating)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ViewportFramePreferenceKey.self,
                    value: proxy.frame(in: .named(Self.panelSpace))
                )
            }
        )
        .overlay(alignment: .center) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }

    private func row(_ index: Int) -> some View {
        let isHighlighted = model.highlightedParagraph == index

        return HStack(alignment: .top, spacing: 0) {
            inputCell(index, isHighlighted: isHighlighted)
                .padding(.trailing, gutter)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            outputCell(index, isHighlighted: isHighlighted)
                .padding(.leading, gutter)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, gutter)
        .padding(.top, index == 0 ? 12 : rowSpacing)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RowFramePreferenceKey.self,
                    value: [index: proxy.frame(in: .named(Self.panelSpace))]
                )
            }
        )
    }

    private func inputCell(_ index: Int, isHighlighted: Bool) -> some View {
        TextField("", text: inputBinding(index), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .lineLimit(1...)
            .focused($focusedParagraph, equals: index)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? Self.sourceHighlight : Color.clear)
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            )
            .overlay(alignment: .topLeading) {
                if index == 0, model.input.isEmpty {
                    Text("Text")
                        .font(.system(size: 17))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.leading, 1)
                        .padding(.top, 1)
                }
            }
            .onSubmit {
                insertParagraph(after: index)
            }
    }

    @ViewBuilder
    private func outputCell(_ index: Int, isHighlighted: Bool) -> some View {
        if index == 0, let message = model.errorMessage, !message.isEmpty {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } else if index == 0, model.isTranslating, model.output.isEmpty {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Translating…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(model.translatedParagraph(at: index))
                .font(.system(size: 17))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHighlighted ? Self.translationHighlight : Color.clear)
                        .padding(.horizontal, -6)
                        .padding(.vertical, -3)
                )
        }
    }

    private var rowCount: Int {
        max(model.sourceParagraphs.count, model.outputParagraphs.count, 1)
    }

    private func inputBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { model.paragraph(at: index) },
            set: { newValue in
                let inserted = model.setParagraph(index, to: newValue)
                guard inserted > 0 else { return }
                DispatchQueue.main.async {
                    focusedParagraph = index + inserted
                }
            }
        )
    }

    private func insertParagraph(after index: Int) {
        model.setParagraph(index, to: model.paragraph(at: index) + "\n")
        DispatchQueue.main.async {
            focusedParagraph = index + 1
        }
    }

    private func handleClick(at point: CGPoint) {
        guard metrics.viewportFrame.contains(point) else { return }

        guard let index = metrics.rowFrames.first(where: { $0.value.contains(point) })?.key else {
            model.clearHighlight()
            return
        }
        model.highlightParagraph(at: index)
    }

    private static let sourceHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.42, green: 0.62, blue: 1.0, alpha: 0.40)
            : NSColor(srgbRed: 0.62, green: 0.78, blue: 1.0, alpha: 0.45)
    })

    private static let translationHighlight = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.0, green: 0.76, blue: 0.87, alpha: 0.58)
            : NSColor(srgbRed: 1.0, green: 0.73, blue: 0.82, alpha: 0.6)
    })

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    private func focusInput() {
        let target = min(max(focusedParagraph ?? 0, 0), max(rowCount - 1, 0))
        focusedParagraph = nil
        DispatchQueue.main.async {
            focusedParagraph = target
        }
    }

    /// Scroll geometry shared with AppKit callbacks, which can arrive between
    /// SwiftUI view updates and must still see the latest positions.
    private final class ScrollMetrics {
        var rowFrames: [Int: CGRect] = [:]
        var viewportFrame: CGRect = .zero
    }
}

private struct RowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ViewportFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Keeps the streaming output pinned to the bottom only while the user has not
/// taken over scrolling. Scroll position is driven through AppKit directly,
/// because `ScrollViewProxy` re-targets rows while streaming and makes the
/// scroller jump under the user's hand.
private struct ScrollFollowObserver: NSViewRepresentable {
    let isTranslating: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isTranslating = isTranslating
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.isTranslating = isTranslating
    }

    final class ObserverView: NSView {
        var isTranslating = false {
            didSet {
                guard isTranslating, !oldValue else { return }
                isFollowing = true
                followToBottom()
            }
        }

        /// Distance from the bottom that still counts as "following the output".
        private let followTolerance: CGFloat = 24

        private var isFollowing = true
        private var isLiveScrollTracking = false
        private weak var observedScrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []
        private var didRetryAttach = false

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attach()
        }

        deinit {
            detach()
        }

        private func attach() {
            guard let scrollView = enclosingScrollView else {
                // The enclosing scroll view may not be in place on the first callback.
                guard window != nil, !didRetryAttach else { return }
                didRetryAttach = true
                DispatchQueue.main.async { [weak self] in
                    self?.attach()
                }
                return
            }
            guard scrollView !== observedScrollView else { return }
            detach()

            observedScrollView = scrollView
            isFollowing = isScrolledToBottom()

            let center = NotificationCenter.default
            var observers: [NSObjectProtocol] = [
                center.addObserver(
                    forName: NSScrollView.willStartLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.isLiveScrollTracking = true
                    self.isFollowing = false
                },
                center.addObserver(
                    forName: NSScrollView.didLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    // Wait for the end of a gesture or thumb drag, otherwise a
                    // mid-drag check could re-pin the view and fight the user.
                    guard !self.isLiveScrollTracking else { return }
                    self.isFollowing = self.isScrolledToBottom()
                },
                center.addObserver(
                    forName: NSScrollView.didEndLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.isLiveScrollTracking = false
                    // Let the scroll view settle before reading its geometry.
                    DispatchQueue.main.async {
                        self.isFollowing = self.isScrolledToBottom()
                    }
                },
            ]

            if let documentView = scrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                observers.append(
                    center.addObserver(
                        forName: NSView.frameDidChangeNotification,
                        object: documentView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.followToBottom()
                    }
                )
            }

            self.observers = observers
        }

        private func detach() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers.removeAll()
            observedScrollView = nil
        }

        private func followToBottom() {
            guard isFollowing, isTranslating,
                  let scrollView = observedScrollView,
                  let documentView = scrollView.documentView else { return }

            let clipView = scrollView.contentView
            let limit = max(0, documentView.bounds.height - clipView.bounds.height)
            let target = documentView.isFlipped ? limit : documentView.bounds.minY

            guard abs(clipView.bounds.origin.y - target) > 0.5 else { return }
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target))
            scrollView.reflectScrolledClipView(clipView)
        }

        /// Reads the scroll view's own geometry instead of SwiftUI preferences,
        /// which lag behind while rows are still being laid out.
        private func isScrolledToBottom() -> Bool {
            guard let scrollView = observedScrollView,
                  let documentView = scrollView.documentView else {
                return true
            }

            let clipView = scrollView.contentView
            let limit = max(0, documentView.bounds.height - clipView.bounds.height)
            let bottom = documentView.isFlipped ? limit : documentView.bounds.minY
            return abs(clipView.bounds.origin.y - bottom) <= followTolerance
        }
    }
}

/// Reports left-click locations without consuming the event, so text editing and
/// text selection keep working while paragraphs can still be highlighted.
private struct MouseDownMonitor: NSViewRepresentable {
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onClick = onClick
    }

    final class MonitorView: NSView {
        var onClick: ((CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()

            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                if let self, let window = self.window, event.window === window {
                    self.onClick?(self.convert(event.locationInWindow, from: nil))
                }
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct StopButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Stop")
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
        .help("Stop translating")
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
                Text(language.name)
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
