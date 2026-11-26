import SwiftUI

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    let openSettings: () -> Void

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
