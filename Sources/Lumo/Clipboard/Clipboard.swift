import Foundation
import AppKit

protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    func string() -> String?
    func setString(_ s: String)
}

final class NSPasteboardClipboard: Clipboard {
    private let pb = NSPasteboard.general
    var changeCount: Int { pb.changeCount }
    func string() -> String? { pb.string(forType: .string) }
    func setString(_ s: String) {
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

final class FakeClipboard: Clipboard {
    private var _string: String?
    private(set) var changeCount: Int = 0
    func string() -> String? { _string }
    func setString(_ s: String) {
        _string = s
        changeCount += 1
    }
}
