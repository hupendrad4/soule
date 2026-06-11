import Foundation

struct TopicAnalysis: Codable, Sendable, Identifiable {
    let id: String
    let entryId: String
    let topic: String
    let sentiment: Double
    let confidence: Double
    let energy: Double?
    let keywords: [String]
    let createdAt: TimeInterval

    init(id: String = UUID().uuidString, entryId: String, topic: String, sentiment: Double, confidence: Double = 0.5, energy: Double? = nil, keywords: [String] = []) {
        self.id = id
        self.entryId = entryId
        self.topic = topic
        self.sentiment = sentiment
        self.confidence = confidence
        self.energy = energy
        self.keywords = keywords
        self.createdAt = Date().timeIntervalSince1970
    }
}
