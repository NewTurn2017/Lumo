import XCTest
import CoreGraphics
@testable import Lumo

final class PromptBuilderTests: XCTestCase {
    func test_imageToKorean_systemIsKoreanPersona() {
        let m = PromptBuilder.messages(source: .image(fakeCG()), target: .korean, base64: "ZmFrZQ==")
        XCTAssertTrue(m.system.contains("숙련된 통역사"))
        XCTAssertTrue(m.system.contains("한국어"))
        XCTAssertEqual(m.userContent, "이 이미지 속 텍스트를 한국어로 통역")
        XCTAssertEqual(m.images, ["ZmFrZQ=="])
    }

    func test_textToKorean_systemIsKoreanPersona() {
        let m = PromptBuilder.messages(source: .text("Hello"), target: .korean, base64: nil)
        XCTAssertTrue(m.system.contains("숙련된 통역사"))
        XCTAssertEqual(m.userContent, "다음 텍스트를 한국어로 통역:\n\nHello")
        XCTAssertNil(m.images)
    }

    func test_textToEnglish_systemIsEnglishPersona() {
        let m = PromptBuilder.messages(source: .text("안녕"), target: .english, base64: nil)
        XCTAssertTrue(m.system.contains("skilled interpreter"))
        XCTAssertTrue(m.system.contains("English"))
        XCTAssertEqual(m.userContent, "Translate the following text into natural English:\n\n안녕")
        XCTAssertNil(m.images)
    }

    private func fakeCG() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
