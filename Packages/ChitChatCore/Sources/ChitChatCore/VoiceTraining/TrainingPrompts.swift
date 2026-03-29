import Foundation

public struct TrainingPrompt: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let category: Category
    public let estimatedDuration: TimeInterval

    public enum Category: String, Sendable {
        case conversational
        case technical
        case business
        case numbers
        case dictation
    }
}

/// Ten training passages designed to capture diverse speech patterns.
/// Each passage is 30-60 seconds of speech and covers different phonemes,
/// vocabulary, and punctuation patterns.
public enum TrainingPrompts {
    public static let all: [TrainingPrompt] = [
        TrainingPrompt(
            id: "conv_1",
            title: "Casual Conversation",
            text: "Hey, I was thinking we could grab lunch tomorrow around noon. There's a new Thai place on Market Street that just opened. Sarah mentioned it's really good, especially the pad thai and green curry. Let me know if that works for you, or if you'd prefer something else.",
            category: .conversational,
            estimatedDuration: 20
        ),

        TrainingPrompt(
            id: "tech_1",
            title: "Technical Discussion",
            text: "The API endpoint returns a JSON response with a status code of 200 for successful requests. We need to handle the pagination using cursor-based tokens. The rate limit is 1,000 requests per minute, and we should implement exponential backoff for 429 responses.",
            category: .technical,
            estimatedDuration: 25
        ),

        TrainingPrompt(
            id: "bus_1",
            title: "Business Email",
            text: "Dear Ms. Thompson, Thank you for your proposal regarding the Q3 marketing budget. After reviewing the projected ROI and discussing it with the finance team, we'd like to move forward with Option B. Could you please schedule a follow-up meeting for next Tuesday at 2 PM? Best regards.",
            category: .business,
            estimatedDuration: 25
        ),

        TrainingPrompt(
            id: "num_1",
            title: "Numbers and Dates",
            text: "The meeting is scheduled for March 15th, 2026 at 3:45 PM Eastern Time. The budget is $2.5 million, which is a 12% increase over last year's $2.23 million. Our phone number is 415-555-0198 and the extension is 4072.",
            category: .numbers,
            estimatedDuration: 22
        ),

        TrainingPrompt(
            id: "dict_1",
            title: "Quick Notes",
            text: "Reminder: pick up groceries after work. Need milk, eggs, bread, and olive oil. Also call Dr. Martinez about the appointment on Thursday. Don't forget to submit the expense report by Friday, reference number is TXN-89432.",
            category: .dictation,
            estimatedDuration: 20
        ),

        TrainingPrompt(
            id: "tech_2",
            title: "Code Review",
            text: "I noticed the getUserProfile function doesn't handle the null case when the database query returns no results. We should add a guard clause that returns a 404 error with the message \"User not found.\" Also, the variable name \"tmp\" should be renamed to something more descriptive like \"userSession.\"",
            category: .technical,
            estimatedDuration: 25
        ),

        TrainingPrompt(
            id: "conv_2",
            title: "Giving Directions",
            text: "To get to the office, take Interstate 280 north for about 3 miles, then exit at Brannan Street. Turn left at the second traffic light onto 4th Street. The building is on the right side, number 525. There's a parking garage underneath, and visitor parking is on level B2.",
            category: .conversational,
            estimatedDuration: 23
        ),

        TrainingPrompt(
            id: "bus_2",
            title: "Meeting Summary",
            text: "Action items from today's standup: Jake will finish the authentication module by Wednesday. Lisa is blocked on the design review and needs feedback from the UX team. We agreed to postpone the database migration to next sprint. The retrospective is moved to Friday at 4 PM in Conference Room C.",
            category: .business,
            estimatedDuration: 25
        ),

        TrainingPrompt(
            id: "dict_2",
            title: "Personal Message",
            text: "Happy birthday, Michael! I can't believe you're turning 30. It feels like just yesterday we were roommates in college, staying up late arguing about whether Python or JavaScript was better. Hope your day is amazing. Let's catch up soon over coffee or a video call.",
            category: .dictation,
            estimatedDuration: 22
        ),

        TrainingPrompt(
            id: "tech_3",
            title: "System Description",
            text: "The application uses a microservices architecture deployed on Kubernetes. The main components are the API gateway, which handles routing and authentication; the user service, backed by PostgreSQL; and the notification service, which uses Redis for message queuing and sends emails via SendGrid's SMTP API.",
            category: .technical,
            estimatedDuration: 28
        ),
    ]
}
