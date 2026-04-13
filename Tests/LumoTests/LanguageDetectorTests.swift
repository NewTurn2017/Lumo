import XCTest
@testable import Lumo

final class LanguageDetectorTests: XCTestCase {
    func test_pureEnglish_isNotKorean() {
        XCTAssertFalse(LanguageDetector.isKorean("Hello, world!"))
    }
    func test_pureKorean_isKorean() {
        XCTAssertTrue(LanguageDetector.isKorean("안녕하세요, 세상입니다."))
    }
    func test_mostlyKoreanWithEnglishTerm_isKorean() {
        XCTAssertTrue(LanguageDetector.isKorean("이 모델은 gemma4:e4b 이며 한국어 지원이 뛰어납니다."))
    }
    func test_mostlyEnglishWithOneHangul_isNotKorean() {
        XCTAssertFalse(LanguageDetector.isKorean("The model gemma4 supports 한국 and more."))
    }
    func test_punctuationAndDigitsIgnored() {
        XCTAssertTrue(LanguageDetector.isKorean("!!! 안녕 123 ???"))
    }
    func test_emptyString_isNotKorean() {
        XCTAssertFalse(LanguageDetector.isKorean(""))
    }
    func test_whitespaceOnly_isNotKorean() {
        XCTAssertFalse(LanguageDetector.isKorean("   \n\t "))
    }
    func test_emojiOnly_isNotKorean() {
        XCTAssertFalse(LanguageDetector.isKorean("😀🚀✨"))
    }
    func test_exactlyFiftyPercent_isKorean() {
        // Two letters: 1 Hangul, 1 Latin → ratio 0.5 → treated as Korean (>= 0.5)
        XCTAssertTrue(LanguageDetector.isKorean("가a"))
    }
}
