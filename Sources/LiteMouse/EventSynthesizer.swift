import AppKit
import CoreGraphics
import Foundation
import LiteMouseCore

enum EventSynthesizer {
    /// Magic tag placed in `eventSourceUserData` to bypass our own event tap in O(1).
    static let magicUserData: Int64 = 0x4C4D5345 // "LMSE"

    // Private CoreGraphics / IOHID gesture constants (verified against WebKit CoreGraphicsTestSPI & IOHIDEventTypes)
    private static let eventTypeGesture = CGEventType(rawValue: 29)!
    private static let fieldGestureHIDType = CGEventField(rawValue: 110)!
    private static let fieldGestureSwipeValue = CGEventField(rawValue: 115)!
    private static let fieldGesturePhase = CGEventField(rawValue: 132)!

    private static let iohidEventTypeNavigationSwipe: Int64 = 16
    private static let cgsGesturePhaseBegan: Int64 = 1
    private static let cgsGesturePhaseEnded: Int64 = 4
    private static let iohidSwipeLeft: Int64 = 0x04
    private static let iohidSwipeRight: Int64 = 0x08

    // Virtual key codes for '[' and ']' on ANSI layout
    private static let keyCodeLeftBracket: CGKeyCode = 0x21
    private static let keyCodeRightBracket: CGKeyCode = 0x1E

    static func postNavigationSwipe(_ direction: NavigationDirection) {
        guard let began = CGEvent(source: nil),
              let ended = CGEvent(source: nil) else {
            return
        }

        let swipeMask: Int64 = (direction == .back) ? iohidSwipeLeft : iohidSwipeRight

        began.type = eventTypeGesture
        began.setIntegerValueField(fieldGestureHIDType, value: iohidEventTypeNavigationSwipe)
        began.setIntegerValueField(fieldGesturePhase, value: cgsGesturePhaseBegan)
        began.setIntegerValueField(fieldGestureSwipeValue, value: swipeMask)
        began.setIntegerValueField(.eventSourceUserData, value: magicUserData)

        ended.type = eventTypeGesture
        ended.setIntegerValueField(fieldGestureHIDType, value: iohidEventTypeNavigationSwipe)
        ended.setIntegerValueField(fieldGesturePhase, value: cgsGesturePhaseEnded)
        ended.setIntegerValueField(.eventSourceUserData, value: magicUserData)

        began.post(tap: .cgSessionEventTap)
        ended.post(tap: .cgSessionEventTap)
    }

    static func postCommandBracket(_ direction: NavigationDirection) {
        let keyCode = (direction == .back) ? keyCodeLeftBracket : keyCodeRightBracket
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        up.setIntegerValueField(.eventSourceUserData, value: magicUserData)

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// Posts a continuous pixel-unit scroll frame without trackpad gesture phases
    /// so horizontal Shift+scroll never accidentally triggers browser back/forward swipe.
    static func postSmoothScroll(dx: Int32, dy: Int32, modifierFlags: CGEventFlags) {
        guard dx != 0 || dy != 0 else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else {
            return
        }

        let keptModifiers: CGEventFlags = modifierFlags.intersection([
            .maskShift, .maskControl, .maskAlternate, .maskCommand,
        ])
        if !keptModifiers.isEmpty {
            event.flags = keptModifiers
        }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        event.post(tap: .cgSessionEventTap)
    }
}
