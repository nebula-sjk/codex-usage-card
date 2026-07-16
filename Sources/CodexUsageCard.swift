import Cocoa
import Foundation
import CoreGraphics

private struct UsageSnapshot {
    let weeklyUsed: Int
    let weeklyResetAfter: Int
    let weeklyResetAt: Int
    let resetsAvailable: Int
    let resetCardExpiryAt: Int
    let plan: String
    let sampledAt: Date
}

private struct CardPalette {
    let start: NSColor
    let end: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let track: NSColor
    let accent: NSColor
    let statusText: NSColor
    let rowFill: NSColor
    let rowBorder: NSColor

    static let cool = CardPalette(
        start: NSColor(calibratedRed: 0.86, green: 0.93, blue: 0.98, alpha: 1),
        end: NSColor(calibratedRed: 0.80, green: 0.92, blue: 0.90, alpha: 1),
        primaryText: NSColor(calibratedWhite: 0.08, alpha: 0.92),
        secondaryText: NSColor(calibratedWhite: 0.08, alpha: 0.58),
        track: NSColor.white.withAlphaComponent(0.45),
        accent: NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.32, alpha: 0.95),
        statusText: NSColor(calibratedRed: 0.10, green: 0.47, blue: 0.22, alpha: 0.95),
        rowFill: NSColor.white.withAlphaComponent(0.23),
        rowBorder: NSColor.white.withAlphaComponent(0.32)
    )

    static let warm = CardPalette(
        start: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.87, alpha: 1),
        end: NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.75, alpha: 1),
        primaryText: NSColor(calibratedWhite: 0.08, alpha: 0.92),
        secondaryText: NSColor(calibratedWhite: 0.08, alpha: 0.58),
        track: NSColor.white.withAlphaComponent(0.46),
        accent: NSColor(calibratedRed: 0.88, green: 0.57, blue: 0.10, alpha: 0.95),
        statusText: NSColor(calibratedRed: 0.60, green: 0.34, blue: 0.05, alpha: 0.95),
        rowFill: NSColor.white.withAlphaComponent(0.24),
        rowBorder: NSColor.white.withAlphaComponent(0.34)
    )

    static let critical = CardPalette(
        start: NSColor(calibratedRed: 0.96, green: 0.89, blue: 0.83, alpha: 1),
        end: NSColor(calibratedRed: 0.88, green: 0.83, blue: 0.85, alpha: 1),
        primaryText: NSColor(calibratedWhite: 0.08, alpha: 0.92),
        secondaryText: NSColor(calibratedWhite: 0.08, alpha: 0.58),
        track: NSColor.white.withAlphaComponent(0.48),
        accent: NSColor(calibratedRed: 0.88, green: 0.25, blue: 0.22, alpha: 0.95),
        statusText: NSColor(calibratedRed: 0.66, green: 0.15, blue: 0.12, alpha: 0.95),
        rowFill: NSColor.white.withAlphaComponent(0.25),
        rowBorder: NSColor.white.withAlphaComponent(0.36)
    )

    static func forRemaining(_ remaining: Int) -> CardPalette {
        if remaining < 30 { return .critical }
        if remaining < 60 { return .warm }
        return .cool
    }
}

private final class UsageReader {
    private let databasePath = NSString(string: "~/.codex/logs_2.sqlite").expandingTildeInPath

    func read() -> UsageSnapshot? {
        if let preview = previewSnapshot() {
            return preview
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            databasePath,
            "SELECT feedback_log_body FROM logs " +
            "WHERE ((feedback_log_body LIKE '%\"x-codex-primary-window-minutes\":%' " +
            "AND feedback_log_body LIKE '%\"x-codex-primary-used-percent\":%') " +
            "OR (feedback_log_body LIKE '%x-codex-primary-window-minutes =>%' " +
            "AND feedback_log_body LIKE '%x-codex-primary-used-percent =>%')) " +
            "ORDER BY id DESC LIMIT 80;"
        ]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: output, encoding: .utf8) else { return nil }

            let primaryWindow = intValue(for: "x-codex-primary-window-minutes", in: text) ?? 0
            let secondaryWindow = intValue(for: "x-codex-secondary-window-minutes", in: text) ?? 0
            let primaryUsed = intValue(for: "x-codex-primary-used-percent", in: text)
            let secondaryUsed = intValue(for: "x-codex-secondary-used-percent", in: text)
            let primaryAfter = intValue(for: "x-codex-primary-reset-after-seconds", in: text) ?? 0
            let secondaryAfter = intValue(for: "x-codex-secondary-reset-after-seconds", in: text) ?? 0
            let primaryAt = intValue(for: "x-codex-primary-reset-at", in: text) ?? 0
            let secondaryAt = intValue(for: "x-codex-secondary-reset-at", in: text) ?? 0

            let weeklyUsed: Int?
            let weeklyAfter: Int
            let weeklyAt: Int
            if primaryWindow >= 10_000 {
                weeklyUsed = primaryUsed
                weeklyAfter = primaryAfter
                weeklyAt = primaryAt
            } else if secondaryWindow >= 10_000 {
                weeklyUsed = secondaryUsed
                weeklyAfter = secondaryAfter
                weeklyAt = secondaryAt
            } else if primaryWindow >= secondaryWindow {
                weeklyUsed = primaryUsed
                weeklyAfter = primaryAfter
                weeklyAt = primaryAt
            } else {
                weeklyUsed = secondaryUsed
                weeklyAfter = secondaryAfter
                weeklyAt = secondaryAt
            }

            guard let weeklyUsed else { return nil }
            let resetKeys = [
                "x-codex-usage-reset-available",
                "x-codex-resets-available",
                "x-codex-reset-credits",
                "usage_reset_count",
                "usage_limit_reset_count",
                "rate_limit_reset_available",
                "resets_available"
            ]
            // The current response headers do not expose this UI-only count.
            // Keep the value shown by the user's official panel until a future field appears.
            let resetsAvailable = resetKeys.compactMap { intValue(for: $0, in: text) }.first ?? 1
            let resetCardExpiryKeys = [
                "x-codex-usage-reset-expiry",
                "x-codex-usage-reset-expires-at",
                "x-codex-usage-reset-expiration-at",
                "x-codex-reset-expires-at",
                "x-codex-reset-expiration-at",
                "x-codex-credit-reset-expiry",
                "x-codex-credit-reset-expires-at",
                "x-codex-credits-reset-at",
                "x-codex-credits-expiry",
                "x-codex-credits-expiration",
                "x-codex-credits-expires-at",
                "x-codex-credits-expiration-at",
                "x-codex-full-reset-expiry",
                "x-codex-full-reset-expires-at",
                "x-codex-reset-expiry-at",
                "usage_reset_expiry",
                "usage_reset_expires_at",
                "usage_reset_expire_at",
                "usage_limit_reset_expires_at",
                "reset_card_expiry_at",
                "reset_card_expires_at"
            ]
            // Reset-card expiry is intentionally separate from the weekly
            // window reset. If several cards are present, use the nearest
            // future expiry so the UI reflects the next card to expire.
            let resetCardExpiryAt = resetCardExpiryKeys
                .flatMap { timestampValues(for: $0, in: text) }
                .filter { $0 > 0 }
                .min() ?? officialPanelFallbackExpiryAt()
            let plan = capture("x-codex-plan-type", in: text)?.capitalized ?? "Codex"

            return UsageSnapshot(
                weeklyUsed: weeklyUsed,
                weeklyResetAfter: weeklyAfter,
                weeklyResetAt: weeklyAt,
                resetsAvailable: resetsAvailable,
                resetCardExpiryAt: resetCardExpiryAt,
                plan: plan,
                sampledAt: Date()
            )
        } catch {
            return nil
        }
    }

    // Intended for release screenshots and UI regression checks only. This
    // override never reads or changes the user's local Codex database.
    private func previewSnapshot() -> UsageSnapshot? {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_USAGE_CARD_PREVIEW_REMAINING"],
              let remaining = Int(raw),
              (0...100).contains(remaining) else { return nil }
        let now = Date()
        return UsageSnapshot(
            weeklyUsed: 100 - remaining,
            weeklyResetAfter: 3 * 86_400,
            weeklyResetAt: Int(now.addingTimeInterval(3 * 86_400).timeIntervalSince1970),
            resetsAvailable: 1,
            resetCardExpiryAt: Int(now.addingTimeInterval(12 * 86_400).timeIntervalSince1970),
            plan: "Plus",
            sampledAt: now
        )
    }

    private func intValue(for key: String, in text: String) -> Int? {
        guard let value = capture(key, in: text) else { return nil }
        return Int(value)
    }

    private func timestampValues(for key: String, in text: String) -> [Int] {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "\\\"" + escaped + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            escaped + "\\s*(?:=>|[=:])\\s*\\\"?([^,}\\\"\\s]+)"
        ]
        let rawValues = patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[valueRange])
            }
        }
        return rawValues.compactMap { raw in
            if let value = Int(raw) {
                return value > 2_000_000_000_000 ? value / 1000 : value
            }
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: raw).map { Int($0.timeIntervalSince1970) }
        }
    }

    private func capture(_ key: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "\\\"" + escaped + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            escaped + "\\s*(?:=>|[=:])\\s*\\\"?([^,}\\\"\\s]+)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: text) {
                return String(text[valueRange])
            }
        }
        return nil
    }

    private func officialPanelFallbackExpiryAt() -> Int {
        // The response headers currently omit reset-card expiry. Retain the
        // latest verified official-panel value only until that date passes;
        // a future server value always takes precedence.
        var components = DateComponents()
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current
        components.year = 2026
        components.month = 8
        components.day = 13
        components.hour = 23
        components.minute = 59
        guard let date = components.date, date > Date() else { return 0 }
        return Int(date.timeIntervalSince1970)
    }

}

private final class UsageBar: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var fillColor = CardPalette.cool.accent {
        didSet { needsDisplay = true }
    }
    var trackColor = CardPalette.cool.track {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        trackColor.setFill()
        track.fill()

        let fillWidth = max(4, bounds.width * min(max(progress, 0), 1))
        let fillRect = NSRect(x: 0, y: 0, width: min(bounds.width, fillWidth), height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        // The bar represents the remaining quota, matching the adjacent label.
        fillColor.setFill()
        fill.fill()
    }
}

private final class ResetRowButton: NSButton {
    var countText: String = "可用1次" {
        didSet {
            setAccessibilityLabel("限额重置次数（仅显示作用），\(countText)，\(expiryText)")
            needsDisplay = true
        }
    }
    var expiryText: String = "最近一次重置：日期读取中…" {
        didSet {
            setAccessibilityLabel("限额重置次数（仅显示作用），\(countText)，\(expiryText)")
            needsDisplay = true
        }
    }
    var rowFillColor = CardPalette.cool.rowFill {
        didSet { needsDisplay = true }
    }
    var rowBorderColor = CardPalette.cool.rowBorder {
        didSet { needsDisplay = true }
    }
    var labelColor = CardPalette.cool.primaryText {
        didSet { needsDisplay = true }
    }
    var chevronColor = CardPalette.cool.primaryText {
        didSet { needsDisplay = true }
    }

    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let row = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        let rowColor = isHighlighted
            ? NSColor.white.withAlphaComponent(0.42)
            : (isHovering ? NSColor.white.withAlphaComponent(0.34) : rowFillColor)
        rowColor.setFill()
        row.fill()
        rowBorderColor.setStroke()
        row.lineWidth = 1
        row.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: labelColor
        ]
        let titleRect = NSRect(x: 14, y: bounds.height - 22, width: 160, height: 17)
        "限额重置次数（仅显示作用）".draw(in: titleRect, withAttributes: titleAttributes)

        let expiryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: labelColor.withAlphaComponent(0.54)
        ]
        let expiryRect = NSRect(x: 14, y: 5, width: 158, height: 14)
        expiryText.draw(in: expiryRect, withAttributes: expiryAttributes)

        let countFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: countFont,
            .foregroundColor: NSColor.white
        ]
        let countWidth = max(70, countText.size(withAttributes: countAttributes).width + 20)
        let pillRect = NSRect(
            x: bounds.width - countWidth - 34,
            y: (bounds.height - 24) / 2,
            width: countWidth,
            height: 24
        )
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.22, alpha: isHighlighted ? 1.0 : 0.96).setFill()
        pill.fill()
        let countSize = countText.size(withAttributes: countAttributes)
        let countOrigin = NSPoint(
            x: pillRect.midX - countSize.width / 2,
            // NSFont.descender is negative. Use the full ascent-to-descent
            // height so the label is optically centered inside the pill.
            y: pillRect.midY - (countFont.ascender - countFont.descender) / 2
        )
        countText.draw(at: countOrigin, withAttributes: countAttributes)

        let midY = bounds.midY
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: bounds.width - 24, y: midY - 2))
        chevron.line(to: NSPoint(x: bounds.width - 20, y: midY + 2))
        chevron.line(to: NSPoint(x: bounds.width - 16, y: midY - 2))
        chevron.lineWidth = 1.4
        chevronColor.setStroke()
        chevron.stroke()

        if window?.firstResponder === self {
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            focus.lineWidth = 2
            focus.stroke()
        }
    }

}

private final class MacCloseButton: NSButton {
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = NSRect(x: (bounds.width - 20) / 2, y: (bounds.height - 20) / 2, width: 20, height: 20)
        let circle = NSBezierPath(ovalIn: circleRect)
        let circleColor = isHighlighted || isHovering
            ? NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 0.98)
            : NSColor(calibratedRed: 0.84, green: 0.30, blue: 0.28, alpha: 0.72)
        circleColor.setFill()
        circle.fill()

        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: circleRect.minX + 6.5, y: circleRect.minY + 6.5))
        cross.line(to: NSPoint(x: circleRect.maxX - 6.5, y: circleRect.maxY - 6.5))
        cross.move(to: NSPoint(x: circleRect.minX + 6.5, y: circleRect.maxY - 6.5))
        cross.line(to: NSPoint(x: circleRect.maxX - 6.5, y: circleRect.minY + 6.5))
        cross.lineWidth = 1.4
        NSColor.white.withAlphaComponent(isHovering ? 0.96 : 0.82).setStroke()
        cross.stroke()
    }
}

private final class ResizeGripView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        for offset in stride(from: 4.0, through: 10.0, by: 3.0) {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: bounds.width - offset, y: 2))
            line.line(to: NSPoint(x: bounds.width - 2, y: offset))
            line.lineWidth = 1
            line.stroke()
        }
    }
}

private final class ResizablePanel: NSPanel {
    private var isResizing = false
    private var startPoint = NSPoint.zero
    private var startFrame = NSRect.zero
    private let gripSize: CGFloat = 18
    var resizingEnabled = true
    var expandedMinimumSize = NSSize(width: 250, height: 200)
    var onPointerDownChanged: ((Bool) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            onPointerDownChanged?(true)
            let point = event.locationInWindow
            if resizingEnabled && point.x >= frame.width - gripSize && point.y <= gripSize {
                isResizing = true
                startPoint = point
                startFrame = frame
                return
            }
        case .leftMouseDragged where isResizing:
            let point = event.locationInWindow
            let deltaX = point.x - startPoint.x
            let deltaY = point.y - startPoint.y
            let minimum = expandedMinimumSize
            let newWidth = max(minimum.width, startFrame.width + deltaX)
            let newHeight = max(minimum.height, startFrame.height + deltaY)
            var newFrame = startFrame
            newFrame.size = NSSize(width: newWidth, height: newHeight)
            newFrame.origin.y = startFrame.maxY - newHeight
            setFrame(newFrame, display: true)
            return
        case .leftMouseUp:
            isResizing = false
            onPointerDownChanged?(false)
        default:
            break
        }
        super.sendEvent(event)
    }
}

private final class CardView: NSView {
    var titleLabel: NSTextField!
    var planLabel: NSTextField!
    var closeButton: NSButton!
    var weeklyTitleLabel: NSTextField!
    var weeklyValueLabel: NSTextField!
    var weeklyBar: UsageBar!
    var weeklyResetLabel: NSTextField!
    var resetRowButton: ResetRowButton!
    var sampledLabel: NSTextField!
    var resizeGrip: ResizeGripView!
    var palette = CardPalette.cool {
        didSet { applyPalette() }
    }
    var remainingPercent = 100 {
        didSet { needsDisplay = true }
    }
    var isCollapsed = false {
        didSet { updateCollapsedState() }
    }
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func layout() {
        super.layout()
        if isCollapsed { return }
        let width = bounds.width
        let height = bounds.height

        titleLabel.frame = NSRect(x: 24, y: height - 34, width: 145, height: 18)
        planLabel.frame = NSRect(x: max(160, width - 78), y: height - 34, width: 42, height: 18)
        closeButton.frame = NSRect(x: width - 52, y: height - 50, width: 44, height: 44)

        // Keep the lower content anchored from the bottom up so resizing never
        // makes the reset text collide with the action row or the card border.
        let rowY: CGFloat = 18
        let rowHeight: CGFloat = 44
        let resetTextY = rowY + rowHeight + 5
        let barY = resetTextY + 19
        let valueY = barY + 10
        let titleY = valueY + 46

        weeklyTitleLabel.frame = NSRect(x: 24, y: titleY, width: 160, height: 17)
        weeklyValueLabel.frame = NSRect(x: 24, y: valueY, width: 140, height: 46)
        weeklyBar.frame = NSRect(x: 24, y: barY, width: max(100, width - 48), height: 7)
        weeklyResetLabel.frame = NSRect(x: 24, y: resetTextY, width: max(100, width - 48), height: 14)

        resetRowButton.frame = NSRect(x: 20, y: rowY, width: max(180, width - 40), height: rowHeight)
        sampledLabel.frame = NSRect(x: 24, y: 4, width: max(100, width - 48), height: 11)
        resizeGrip.frame = NSRect(x: width - 15, y: 3, width: 12, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isCollapsed {
            drawOrb()
            return
        }
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        NSGradient(colors: [palette.start, palette.end])?.draw(in: bounds, angle: -24)
        NSGraphicsContext.restoreGraphicsState()

        // Match the expanded card border to the compact orb's semantic
        // status ring while keeping it softer for a desktop-sized surface.
        palette.accent.withAlphaComponent(0.68).setStroke()
        background.lineWidth = 1.25
        background.stroke()
    }

    private func updateCollapsedState() {
        subviews.forEach { view in
            view.isHidden = isCollapsed || view === closeButton
        }
        needsLayout = true
        needsDisplay = true
    }

    private func drawOrb() {
        let orbRect = bounds.insetBy(dx: 3, dy: 3)
        let orb = NSBezierPath(ovalIn: orbRect)
        NSGraphicsContext.saveGraphicsState()
        orb.addClip()
        NSGradient(colors: [palette.start, palette.end])?.draw(in: orbRect, angle: -24)
        NSGraphicsContext.restoreGraphicsState()

        // Reuse the card's semantic status accent so the compact orb carries
        // the same three-level meaning as the expanded card.
        palette.accent.withAlphaComponent(0.92).setStroke()
        orb.lineWidth = 1.5
        orb.stroke()

        let statusDotRect = NSRect(x: bounds.width - 13, y: bounds.height - 13, width: 6, height: 6)
        let statusDot = NSBezierPath(ovalIn: statusDotRect)
        palette.accent.setFill()
        statusDot.fill()

        let percent = "\(remainingPercent)%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.primaryText
        ]
        let size = percent.size(withAttributes: attributes)
        percent.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - (font.ascender - font.descender) / 2),
            withAttributes: attributes
        )
    }

    private func applyPalette() {
        titleLabel?.textColor = palette.primaryText
        planLabel?.textColor = palette.statusText
        weeklyTitleLabel?.textColor = palette.secondaryText
        weeklyValueLabel?.textColor = palette.primaryText
        weeklyResetLabel?.textColor = palette.secondaryText
        sampledLabel?.textColor = palette.secondaryText
        weeklyBar?.fillColor = palette.accent
        weeklyBar?.trackColor = palette.track
        resetRowButton?.rowFillColor = palette.rowFill
        resetRowButton?.rowBorderColor = palette.rowBorder
        resetRowButton?.labelColor = palette.primaryText
        resetRowButton?.chevronColor = palette.primaryText
        needsDisplay = true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cardSize = NSSize(width: 320, height: 200)
    private let ballSize = NSSize(width: 50, height: 50)
    private let reader = UsageReader()
    private var window: ResizablePanel!
    private var weeklyValueLabel: NSTextField!
    private var weeklyResetLabel: NSTextField!
    private var weeklyBar: UsageBar!
    private var resetCountLabel: NSTextField!
    private var sampledLabel: NSTextField!
    private var planLabel: NSTextField!
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var codexVisibilityTimer: Timer?
    private var codexWindowVisible = false
    private var lastUpdateText = "等待最近一次 Codex 请求…"
    private var collapseWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var isPointerDown = false
    private let startsExpandedForPreview = ProcessInfo.processInfo.environment["CODEX_USAGE_CARD_PREVIEW_EXPANDED"] == "1"
    private let previewScreenshotPath = ProcessInfo.processInfo.environment["CODEX_USAGE_CARD_PREVIEW_SCREENSHOT_PATH"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildWindow()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if !startsExpandedForPreview {
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
                self?.pollHoverState()
            }
        }
        codexVisibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.50, repeats: true) { [weak self] _ in
            self?.updateCodexWindowVisibility()
        }
        updateCodexWindowVisibility()
        if previewScreenshotPath != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.writePreviewScreenshot()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hoverTimer?.invalidate()
        codexVisibilityTimer?.invalidate()
    }

    private func buildWindow() {
        let frame = NSRect(origin: .zero, size: cardSize)
        window = ResizablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.minSize = ballSize
        window.expandedMinimumSize = NSSize(width: 250, height: 200)
        window.resizingEnabled = false

        let content = CardView(frame: frame)
        content.autoresizingMask = [.width, .height]
        content.setAccessibilityElement(true)
        content.setAccessibilityRole(.group)
        content.setAccessibilityLabel("Codex 用量卡片")
        window.contentView = content

        content.titleLabel = label("CODEX · …", size: 11, weight: .medium, color: CardPalette.cool.primaryText)
        content.titleLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        content.planLabel = label("充足", size: 10, weight: .medium, color: CardPalette.cool.statusText, alignment: .right)
        planLabel = content.planLabel
        content.closeButton = MacCloseButton(title: "", target: self, action: #selector(closeCard))
        content.closeButton.isBordered = false
        content.closeButton.isHidden = true
        content.closeButton.isEnabled = false
        content.closeButton.target = nil
        content.closeButton.setAccessibilityLabel("关闭使用量卡片")
        content.closeButton.toolTip = "关闭使用量卡片"

        content.weeklyTitleLabel = label("每周使用限额", size: 11, weight: .medium, color: CardPalette.cool.secondaryText)
        weeklyValueLabel = label("—%", size: 36, weight: .regular, color: CardPalette.cool.primaryText, alignment: .left)
        content.weeklyValueLabel = weeklyValueLabel
        weeklyBar = UsageBar(frame: .zero)
        content.weeklyBar = weeklyBar
        weeklyResetLabel = label("重置日期读取中…", size: 10, weight: .regular, color: CardPalette.cool.secondaryText)
        content.weeklyResetLabel = weeklyResetLabel

        let resetRowButton = ResetRowButton(title: "", target: self, action: #selector(resetRowActivated))
        resetRowButton.isBordered = false
        resetRowButton.setAccessibilityLabel("限额重置次数（仅显示作用），不支持直接重置")
        resetRowButton.toolTip = "限额重置次数（仅显示作用），不支持直接重置"
        content.resetRowButton = resetRowButton
        content.sampledLabel = label("等待最近一次 Codex 请求…", size: 9, weight: .regular, color: CardPalette.cool.secondaryText)
        sampledLabel = content.sampledLabel
        content.resizeGrip = ResizeGripView(frame: .zero)

        let views: [NSView] = [
            content.titleLabel, content.planLabel, content.closeButton,
            content.weeklyTitleLabel, content.weeklyValueLabel, content.weeklyBar, content.weeklyResetLabel,
            content.resetRowButton,
            content.sampledLabel, content.resizeGrip
        ]
        views.forEach { content.addSubview($0) }
        content.palette = .cool
        content.onHoverChanged = { [weak self] hovering in
            self?.handleHover(hovering)
        }
        window.onPointerDownChanged = { [weak self] isDown in
            self?.handlePointerDown(isDown)
        }

        let expanded = defaultExpandedFrame()
        window.setFrame(expanded, display: false)
        content.isCollapsed = !startsExpandedForPreview
        window.setFrame(startsExpandedForPreview ? expanded : collapsedFrame(from: expanded), display: false)
        window.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func writePreviewScreenshot() {
        guard let path = previewScreenshotPath,
              let content = window.contentView else { return }
        defer { NSApp.terminate(nil) }
        window.makeFirstResponder(nil)
        content.layoutSubtreeIfNeeded()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = max(1, Int(content.bounds.width * scale))
        let height = max(1, Int(content.bounds.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        bitmap.size = content.bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: content.bounds).fill()
        content.cacheDisplay(in: content.bounds, to: bitmap)
        NSGraphicsContext.restoreGraphicsState()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func defaultExpandedFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            return NSRect(origin: .zero, size: cardSize)
        }
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - cardSize.width - 24,
            y: visible.maxY - cardSize.height - 24,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private func collapsedFrame(from frame: NSRect) -> NSRect {
        NSRect(x: frame.maxX - ballSize.width, y: frame.maxY - ballSize.height, width: ballSize.width, height: ballSize.height)
    }

    private func expandedFrame(from frame: NSRect) -> NSRect {
        NSRect(x: frame.maxX - cardSize.width, y: frame.maxY - cardSize.height, width: cardSize.width, height: cardSize.height)
    }

    private func handleHover(_ hovering: Bool) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if hovering {
            guard !isPointerDown,
                  let content = window.contentView as? CardView,
                  content.isCollapsed,
                  expandWorkItem == nil else { return }
            let workItem = DispatchWorkItem { [weak self] in
                self?.expandWorkItem = nil
                guard let self, !self.isPointerDown else { return }
                self.setCollapsed(false)
            }
            expandWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50, execute: workItem)
            return
        }

        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard let content = window.contentView as? CardView, !content.isCollapsed else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseWorkItem = nil
            self?.setCollapsed(true)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func updateCodexWindowVisibility() {
        let visible = hasVisibleCodexWindow()
        guard visible != codexWindowVisible else { return }
        codexWindowVisible = visible

        if visible {
            repairCollapsedWindowInvariant()
            window.displayIfNeeded()
            window.orderFrontRegardless()
        } else {
            // Remove the panel before changing content/geometry so WindowServer
            // never paints the compact orb in an expanded frame.
            window.orderOut(nil)
            expandWorkItem?.cancel()
            expandWorkItem = nil
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            setCollapsed(true)
        }
    }

    private func hasVisibleCodexWindow() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { info in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { return false }
            let normalized = ownerName.lowercased()
            let isCodexHost = normalized.contains("codex") || normalized == "chatgpt"
            guard isCodexHost,
                  !normalized.contains("usagecard"),
                  !normalized.contains("使用量") else { return false }
            let layer = info[kCGWindowLayer as String] as? Int ?? 1
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let bounds = info[kCGWindowBounds as String] as? [String: Any]
            let width = bounds?["Width"] as? Double ?? 0
            let height = bounds?["Height"] as? Double ?? 0
            return layer == 0 && alpha > 0 && width >= 180 && height >= 100
        }
    }

    private func pollHoverState() {
        guard !isPointerDown else { return }
        let hovering = window.frame.contains(NSEvent.mouseLocation)
        if hovering {
            handleHover(true)
        } else if let content = window.contentView as? CardView, !content.isCollapsed,
                  collapseWorkItem == nil {
            handleHover(false)
        }
    }

    private func handlePointerDown(_ isDown: Bool) {
        isPointerDown = isDown
        if isDown {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        } else {
            pollHoverState()
        }
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard let content = window.contentView as? CardView else { return }
        if collapsed {
            window.resizingEnabled = false
            // Geometry first, content state second. Reversing this order lets
            // drawOrb() render inside the previous 320 x 200 frame as an oval.
            window.setFrame(collapsedFrame(from: window.frame), display: false)
            if !content.isCollapsed {
                content.isCollapsed = true
            }
            window.displayIfNeeded()
            return
        }

        guard content.isCollapsed else { return }
        content.isCollapsed = false
        window.resizingEnabled = true
        let targetFrame = expandedFrame(from: window.frame)
        let duration: TimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
        if duration == 0 {
            window.setFrame(targetFrame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                window.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    private func repairCollapsedWindowInvariant() {
        guard let content = window.contentView as? CardView, content.isCollapsed else { return }
        let size = window.frame.size
        let epsilon: CGFloat = 0.5
        guard abs(size.width - ballSize.width) > epsilon ||
                abs(size.height - ballSize.height) > epsilon else { return }
        window.resizingEnabled = false
        window.setFrame(collapsedFrame(from: window.frame), display: false)
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let snapshot = self.reader.read()
            DispatchQueue.main.async {
                if let snapshot { self.apply(snapshot) }
                else {
                    self.lastUpdateText = "暂未找到最新用量，打开 Codex 后会自动同步"
                    self.sampledLabel.stringValue = self.lastUpdateText
                }
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        let used = min(max(snapshot.weeklyUsed, 0), 100)
        let remaining = 100 - used
        weeklyValueLabel.stringValue = "\(remaining)%"
        weeklyBar.progress = CGFloat(remaining) / 100
        weeklyBar.setAccessibilityLabel("每周使用限额，剩余 \(remaining)%")
        weeklyResetLabel.stringValue = resetText(at: snapshot.weeklyResetAt, after: snapshot.weeklyResetAfter)
        let resetCount = "可用\(max(0, snapshot.resetsAvailable))次"
        let resetExpiry = resetExpiryText(at: snapshot.resetCardExpiryAt)
        window.contentView.flatMap {
            guard let content = $0 as? CardView else { return }
            content.resetRowButton.countText = resetCount
            content.resetRowButton.expiryText = resetExpiry
            content.titleLabel.stringValue = "CODEX · \(snapshot.plan.uppercased())"
        }
        planLabel.stringValue = statusText(for: remaining)
        if let content = window.contentView as? CardView {
            content.remainingPercent = remaining
            content.palette = CardPalette.forRemaining(remaining)
            content.setAccessibilityLabel("Codex \(snapshot.plan)，剩余 \(remaining)%，\(statusText(for: remaining))")
        }
        let time = DateFormatter.localizedString(from: snapshot.sampledAt, dateStyle: .none, timeStyle: .short)
        lastUpdateText = "最近更新 \(time)  ·  每 30 秒自动刷新"
        sampledLabel.stringValue = lastUpdateText
    }

    private func statusText(for remaining: Int) -> String {
        if remaining < 30 { return "告急" }
        if remaining < 60 { return "适中" }
        return "充足"
    }

    private func resetText(at timestamp: Int, after seconds: Int) -> String {
        if timestamp > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "M月d日"
            return "将于 \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))) 重置"
        }
        if seconds > 0 {
            let days = seconds / 86_400
            let hours = (seconds % 86_400) / 3_600
            if days > 0 { return "约 \(days) 天 \(hours) 小时后重置" }
            return "约 \(max(1, hours)) 小时后重置"
        }
        return "重置日期以服务端返回为准"
    }

    private func resetExpiryText(at timestamp: Int) -> String {
        guard timestamp > 0 else { return "重置次数过期：暂未读取" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "M月d日"
        return "重置次数过期：\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp))))"
    }

    @objc private func closeCard() {
        NSApp.terminate(nil)
    }

    @objc private func resetRowActivated() {
        sampledLabel.stringValue = "限额重置次数仅供查看 · 不支持直接重置"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else { return }
            self.sampledLabel.stringValue = self.lastUpdateText
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
