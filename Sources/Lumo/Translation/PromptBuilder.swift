import Foundation

enum PromptBuilder {
    static func messages(source: TranslationSource, target: TargetLanguage, base64: String?) -> BuiltMessages {
        let system = systemPrompt(target: target)
        switch (source, target) {
        case let (.image, .korean):
            return BuiltMessages(
                system: system,
                userContent: "이 이미지 속 텍스트를 한국어로 통역",
                images: base64.map { [$0] }
            )
        case let (.text(t), .korean):
            return BuiltMessages(
                system: system,
                userContent: "다음 텍스트를 한국어로 통역:\n\n\(t)",
                images: nil
            )
        case let (.text(t), .english):
            return BuiltMessages(
                system: system,
                userContent: "Translate the following text into natural English:\n\n\(t)",
                images: nil
            )
        case (.image, .english):
            // Not expected per spec, but keep a safe default.
            return BuiltMessages(
                system: system,
                userContent: "Translate the text in this image into natural English.",
                images: base64.map { [$0] }
            )
        }
    }

    private static func systemPrompt(target: TargetLanguage) -> String {
        switch target {
        case .korean: return koreanSystem
        case .english: return englishSystem
        }
    }

    private static let koreanSystem = """
    당신은 숙련된 통역사다. 입력을 자연스러운 한국어로 의역하라.

    원칙:
    - 직역 금지. 원문의 의도와 뉘앙스를 한국어 독자가 자연스럽게 읽을 수 있게 전달.
    - 문장 흐름, 존댓말/반말 톤, 맥락에 맞는 관용 표현 우선.
    - 기술 용어/고유명사는 필요하면 원어를 괄호로 병기 (예: "추론(reasoning)").
    - UI 문자열(버튼, 메뉴)은 한국어 UI 관례에 맞춘다 (예: "Save" → "저장").
    - 의미가 불명확하면 가장 그럴듯한 해석으로 번역한다. 추측 표시 금지.

    출력 규칙 (엄격):
    - 번역문만 출력. 그 외 일체 금지.
    - 설명, 목록, 헤더, 마크다운, 원문, 추론 과정 금지.
    - 원문의 줄바꿈이 의미 있으면 유지, 단순 줄바꿈이면 합친다.
    - 읽을 수 있는 텍스트가 없으면 정확히 출력: (텍스트 없음)
    """

    private static let englishSystem = """
    You are a skilled interpreter. Render the input as natural English.

    Principles:
    - Avoid literal translation. Convey the original intent and nuance so an English reader reads it fluently.
    - Preserve tone, register, and idiomatic equivalents over word-for-word matches.
    - For technical terms or proper nouns, keep the original in parentheses when useful.
    - For UI strings, use conventional English UI wording.
    - If the meaning is ambiguous, pick the most plausible interpretation. Do not mark guesses.

    Output rules (strict):
    - Output ONLY the English translation. Nothing else.
    - No explanations, lists, headers, markdown, original text, or reasoning traces.
    - Preserve meaningful line breaks; collapse trivial ones.
    - If no readable text, output exactly: (no text)
    """
}
