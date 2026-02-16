import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

struct ChatChoiceMessage: Codable {
    let role: String
    let content: String
}

struct ChatChoice: Codable {
    let index: Int
    let message: ChatChoiceMessage
}

struct ChatResponse: Codable {
    let choices: [ChatChoice]
}

enum OpenAIError: Error {
    case missingAPIKey
    case badResponse
}

final class OpenAIClient {
    private let apiKey: String

    init() throws {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !key.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        self.apiKey = key
    }

    func translate(
        pairs: [String: String],
        targetLanguageCode: String
    ) async throws -> [String: String] {

        let jsonPairs = try JSONSerialization.data(withJSONObject: pairs, options: [.prettyPrinted])
        let jsonString = String(data: jsonPairs, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are a localization engine for Apple iOS apps.
        Input is JSON of { \"key\": \"English text\" }.
        Return ONLY JSON of the same keys mapped to the TRANSLATED text in language code \(targetLanguageCode).
        Do not change keys, do not add or remove keys.
        Preserve placeholders like %@, %d, \\n, and do NOT translate things that look like format specifiers.
        """

        let userPrompt = "Translate the following JSON:\n\(jsonString)"

        let request = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            temperature: 0.2
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("OpenAI error: \(body)")
            throw OpenAIError.badResponse
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw OpenAIError.badResponse
        }

        let parsed = try parseJSONStringDict(from: content)
        guard !parsed.isEmpty || pairs.isEmpty else {
            throw OpenAIError.badResponse
        }

        return parsed
    }

    private func parseJSONStringDict(from content: String) throws -> [String: String] {
        for candidate in jsonCandidates(from: content) {
            guard let data = candidate.data(using: .utf8) else {
                continue
            }
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return dict
            }
        }
        throw OpenAIError.badResponse
    }

    private func jsonCandidates(from content: String) -> [String] {
        var candidates: [String] = [content]

        if let fenced = extractFencedJSON(from: content) {
            candidates.append(fenced)
        }
        if let object = extractJSONObject(from: content) {
            candidates.append(object)
        }

        return candidates
    }

    private func extractFencedJSON(from text: String) -> String? {
        let pattern = #"(?s)```(?:json)?\s*(\{.*?\})\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}
