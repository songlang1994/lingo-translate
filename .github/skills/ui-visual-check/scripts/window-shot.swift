#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO

// Captures one on-screen window with `screencapture -l <windowid>` so UI
// verification never includes the rest of the desktop.
//
//   swift window-shot.swift list
//   swift window-shot.swift shot --title "Settings" --out /tmp/settings.png

private let defaultOwner = "Lingo Translate"

private struct Window {
    let id: Int
    let pid: Int
    let owner: String
    let title: String
    let bounds: CGRect

    var area: CGFloat { bounds.width * bounds.height }
    var sizeDescription: String { "\(Int(bounds.width))x\(Int(bounds.height))" }
}

private struct Options {
    var mode = ""
    var owner: String?
    var title: String?
    var pid: Int?
    var windowID: Int?
    var out: String?
    var waitSeconds: Double = 0
    var keepShadow = false
    var all = false
}

private func writeError(_ message: String) {
    fflush(stdout)
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    writeError(message)
    exit(code)
}

private func usage() -> Never {
    fail(
        """
        Usage:
          window-shot.swift list [--owner NAME] [--title TEXT] [--pid PID]
          window-shot.swift shot [--out PATH] [--owner NAME] [--title TEXT] [--pid PID]
                                [--window ID] [--wait SECONDS] [--all] [--shadow]

        Captures a single on-screen window. It never captures the whole screen.

        Options:
          --owner NAME    Case-insensitive owner substring. Defaults to "\(defaultOwner)"
                          when no other filter is given.
          --title TEXT    Case-insensitive title substring. An empty TEXT matches untitled windows.
          --pid PID       Only windows owned by this process.
          --window ID     Capture this window ID from `list`; skips owner/title/pid filters.
          --out PATH      Output PNG path. Default: window-<id>.png in the temp directory.
          --wait SECONDS  Wait up to SECONDS for a matching window. Default: 0.
          --all           Capture every matching window; files get a -<id> suffix.
          --shadow        Keep the window shadow and the transparent margin around it.

        Exit codes: 0 captured (or listed), 1 no matching window, 2 capture failed, 64 usage.
        """,
        code: 64
    )
}

private func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    guard let mode = args.first, mode == "list" || mode == "shot" else { usage() }
    options.mode = mode
    args.removeFirst()

    var index = 0
    func value(for flag: String) -> String {
        index += 1
        guard index < args.count else { usage() }
        return args[index]
    }

    while index < args.count {
        let argument = args[index]
        switch argument {
        case "--owner":
            options.owner = value(for: argument)
        case "--title":
            options.title = value(for: argument)
        case "--pid":
            guard let pid = Int(value(for: argument)) else { usage() }
            options.pid = pid
        case "--window":
            guard let windowID = Int(value(for: argument)) else { usage() }
            options.windowID = windowID
        case "--out":
            options.out = value(for: argument)
        case "--wait":
            guard let seconds = Double(value(for: argument)), seconds >= 0 else { usage() }
            options.waitSeconds = seconds
        case "--all":
            options.all = true
        case "--shadow":
            options.keepShadow = true
        default:
            usage()
        }
        index += 1
    }

    // With no filter at all, prefer this project's app so `shot` works without
    // repeating --owner.
    if options.owner == nil, options.title == nil, options.pid == nil, options.windowID == nil {
        options.owner = defaultOwner
    }

    return options
}

private func onScreenWindows() -> [Window] {
    let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let entries = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }

    return entries.compactMap { entry in
        guard let id = entry[kCGWindowNumber as String] as? Int,
              let pid = entry[kCGWindowOwnerPID as String] as? Int,
              let owner = entry[kCGWindowOwnerName as String] as? String,
              let layer = entry[kCGWindowLayer as String] as? Int,
              // Normal windows sit at layer 0, floating panels a little above;
              // menu bar extras, the Dock and the menu bar itself sit at 20+.
              layer >= 0, layer < 20,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width >= 1,
              bounds.height >= 1
        else { return nil }

        if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 {
            return nil
        }

        let title = entry[kCGWindowName as String] as? String ?? ""
        return Window(id: id, pid: pid, owner: owner, title: title, bounds: bounds)
    }
}

private func matches(_ window: Window, options: Options) -> Bool {
    if let pid = options.pid, window.pid != pid {
        return false
    }

    if let owner = options.owner, !owner.isEmpty,
       window.owner.range(of: owner, options: .caseInsensitive) == nil {
        return false
    }

    if let title = options.title {
        if title.isEmpty {
            if !window.title.isEmpty { return false }
        } else if window.title.range(of: title, options: .caseInsensitive) == nil {
            return false
        }
    }

    return true
}

private func describe(_ windows: [Window]) -> String {
    windows
        .sorted { ($0.pid, $0.id) < ($1.pid, $1.id) }
        .map { window in
            let title = window.title.isEmpty ? "(untitled)" : "\"\(window.title)\""
            return "id \(window.id)  pid \(window.pid)  \(window.sizeDescription)  \(title)  \(window.owner)"
        }
        .joined(separator: "\n")
}

private func windowsMatching(_ options: Options, waitUpTo seconds: Double) -> [Window] {
    let deadline = Date().addingTimeInterval(seconds)
    while true {
        // `--window` is an explicit choice: capture it even if it does not
        // match the owner or title filters.
        if let windowID = options.windowID {
            return onScreenWindows().filter { $0.id == windowID }
        }

        let matched = onScreenWindows().filter { matches($0, options: options) }
        if !matched.isEmpty || Date() >= deadline {
            return matched
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
}

private func normalizedOutputPath(_ path: String) -> String {
    URL(fileURLWithPath: path).pathExtension.isEmpty ? path + ".png" : path
}

private func outputPath(for window: Window, options: Options, multiple: Bool) -> String {
    let base: String
    if let out = options.out, !out.isEmpty {
        base = normalizedOutputPath(out)
    } else {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lingo-ui-check", isDirectory: true)
        base = directory.appendingPathComponent("window-\(window.id).png").path
    }

    guard multiple else { return base }
    let url = URL(fileURLWithPath: base)
    let ext = url.pathExtension
    let stem = url.deletingPathExtension().path
    return ext.isEmpty ? "\(stem)-\(window.id)" : "\(stem)-\(window.id).\(ext)"
}

private struct ImageInfo {
    let width: Int
    let height: Int
    let isBlank: Bool
}

private func imageInfo(at path: String) -> ImageInfo? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }

    let sampleWidth = 16
    let sampleHeight = 16
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)

    let isBlank = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        let bytes = buffer.bindMemory(to: UInt8.self)
        let red = bytes[0]
        let green = bytes[1]
        let blue = bytes[2]
        let alpha = bytes[3]

        for offset in stride(from: 4, to: bytes.count, by: 4) {
            if bytes[offset] != red || bytes[offset + 1] != green
                || bytes[offset + 2] != blue || bytes[offset + 3] != alpha {
                return false
            }
        }

        // A flat transparent or flat black capture is what macOS returns when
        // the calling process has no Screen Recording permission.
        return alpha == 0 || (red == 0 && green == 0 && blue == 0)
    }

    return ImageInfo(width: image.width, height: image.height, isBlank: isBlank)
}

private func capture(_ window: Window, to path: String, keepShadow: Bool) -> ImageInfo? {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    var arguments = ["-x"]
    if !keepShadow { arguments.append("-o") }
    arguments.append("-l\(window.id)")
    arguments.append(path)
    process.arguments = arguments
    process.standardError = errorPipe
    process.standardOutput = Pipe()

    do {
        try process.run()
    } catch {
        writeError("Could not run screencapture: \(error.localizedDescription)")
        return nil
    }
    process.waitUntilExit()

    let message = String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0 else {
        writeError("screencapture failed for window \(window.id) (status \(process.terminationStatus))\(message.isEmpty ? "" : ": \(message)")")
        return nil
    }

    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
    guard fileSize > 0, let info = imageInfo(at: path) else {
        writeError("screencapture produced no usable image for window \(window.id)\(message.isEmpty ? "" : ": \(message)")")
        return nil
    }

    return info
}

private func filterDescription(_ options: Options) -> String {
    var parts: [String] = []
    if let owner = options.owner { parts.append("--owner \"\(owner)\"") }
    if let title = options.title { parts.append("--title \"\(title)\"") }
    if let pid = options.pid { parts.append("--pid \(pid)") }
    if let windowID = options.windowID { parts.append("--window \(windowID)") }
    return parts.isEmpty ? "(no filter)" : parts.joined(separator: " ")
}

private let options = parseOptions()

switch options.mode {
case "list":
    let windows = windowsMatching(options, waitUpTo: options.waitSeconds)
    guard !windows.isEmpty else {
        var ownerOnly = Options()
        ownerOnly.owner = options.owner
        let sameOwner = options.owner == nil ? [] : onScreenWindows().filter { matches($0, options: ownerOnly) }

        if let owner = options.owner, !sameOwner.isEmpty {
            writeError("No window matched \(filterDescription(options)). On-screen windows of \"\(owner)\":")
            writeError(describe(sameOwner))
        } else {
            writeError("No on-screen window matched \(filterDescription(options)).")
            let everything = onScreenWindows()
            if !everything.isEmpty {
                writeError("Currently on screen:")
                writeError(describe(everything))
            }
        }
        exit(1)
    }
    print(describe(windows))

case "shot":
    var matches = windowsMatching(options, waitUpTo: options.waitSeconds)
    guard !matches.isEmpty else {
        if let windowID = options.windowID {
            writeError("Window \(windowID) is not on screen. Run `list` again after the app opens, or use --wait.")
        } else {
            writeError("No on-screen window matched \(filterDescription(options)). Start the app (for example with --show-panel), or run `list` to inspect visible windows.")
        }
        exit(1)
    }

    let selected: [Window]
    if options.all {
        selected = matches
    } else {
        matches.sort { $0.area > $1.area }
        selected = [matches[0]]
        if matches.count > 1 {
            let others = matches.dropFirst().map { "id \($0.id)" }.joined(separator: ", ")
            writeError("note: \(matches.count) windows matched; capturing the largest. Other matches: \(others). Use --window to pick one.")
        }
    }

    var failed = false
    var suspect = false
    for window in selected {
        let path = outputPath(for: window, options: options, multiple: selected.count > 1)
        guard let info = capture(window, to: path, keepShadow: options.keepShadow) else {
            failed = true
            continue
        }
        let title = window.title.isEmpty ? "(untitled)" : "\"\(window.title)\""
        print("captured window \(window.id) \(title) \(window.sizeDescription) pt, \(info.width)x\(info.height) px -> \(path)")
        if info.isBlank {
            suspect = true
            writeError("warning: window \(window.id) captured as a single flat, transparent, or black image.")
        }
    }

    if failed { exit(2) }
    if suspect {
        writeError("Check the image before trusting it. A flat capture usually means the terminal or editor running this command lacks Screen Recording permission (System Settings → Privacy & Security → Screen Recording).")
    }

default:
    usage()
}
