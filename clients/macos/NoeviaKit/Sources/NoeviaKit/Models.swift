import Foundation

// Response shapes, taken from the route factories that produce them. Required fields are the
// ones the server always writes; everything else decodes leniently so a legacy or newer
// additive field (allowed under v1) never hides the owner's whole workspace.

/// The signed-in account, from apps/web/server/auth.cjs `publicUser()`:
/// `{ id, username, displayName, role, disabled, diaryEnabled, onboarded }`.
public struct User: Decodable, Sendable, Equatable {
    public let id: String
    public let username: String
    public let displayName: String
    /// `admin` or `member` today.
    public let role: String
    public let disabled: Bool
    public let diaryEnabled: Bool
    public let onboarded: Bool

    public var isAdmin: Bool { role == "admin" }

    enum CodingKeys: String, CodingKey { case id, username, displayName, role, disabled, diaryEnabled, onboarded }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? username
        role = try c.decode(String.self, forKey: .role)
        disabled = (try? c.decodeIfPresent(Bool.self, forKey: .disabled)) ?? false
        diaryEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .diaryEnabled)) ?? false
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? true
    }
}

/// `POST /api/auth/login/password` 200 body (auth.cjs `passwordLogin`): `{ user, csrfToken }`.
struct LoginResponse: Decodable, Sendable {
    let user: User
    let csrfToken: String?
}

/// `GET /api/auth/session` body (routes/auth.cjs): `{ user, csrfToken, legacy }`.
struct SessionResponse: Decodable, Sendable {
    let user: User
    let csrfToken: String?
    let legacy: Bool?
}

/// `{ error: string }`, the JSON error body used by every JSON route.
struct ErrorBody: Decodable, Sendable {
    let error: String
}

/// `GET /api/workspace` (apps/web/server/routes/chat-lists.cjs): the account's own projects
/// (internal Diary and chat-attachment projects filtered out) and free chats.
public struct Workspace: Decodable, Sendable, Equatable {
    public let projects: [Project]
    public let freeChats: [ChatMeta]

    enum CodingKeys: String, CodingKey { case projects, freeChats }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decode([Project].self, forKey: .projects)
        freeChats = (try c.decodeIfPresent([ChatMeta].self, forKey: .freeChats)) ?? []
    }
}

/// A project as stored by apps/web/server/projects.cjs `createProject` (type: apps/web/src/types.ts
/// `Project`). Read-only here. File bodies are not kept: only names are decoded.
public struct Project: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let goal: String
    public let instructions: String
    public let icon: String?
    public let color: String?
    public let pinned: Bool
    public let archived: Bool
    public let model: String?
    public let provider: String?
    /// `auto` or `manual`.
    public let routing: String?
    /// App modes the project appears in, e.g. `["chat"]`.
    public let modes: [String]
    public let toolboxes: [String]
    public let fileNames: [String]
    public let chats: [ChatMeta]
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, goal, instructions, icon, color, pinned, archived, model, provider, routing, modes, toolboxes, files, chats, createdAt, updatedAt
    }

    private struct FileName: Decodable { let name: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        goal = c.lenient(String.self, .goal) ?? ""
        instructions = c.lenient(String.self, .instructions) ?? ""
        icon = c.lenient(String.self, .icon)
        color = c.lenient(String.self, .color)
        pinned = c.lenient(Bool.self, .pinned) ?? false
        archived = c.lenient(Bool.self, .archived) ?? false
        model = c.lenient(String.self, .model)
        provider = c.lenient(String.self, .provider)
        routing = c.lenient(String.self, .routing)
        modes = c.lenient([String].self, .modes) ?? ["chat"]
        toolboxes = c.lenient([String].self, .toolboxes) ?? []
        fileNames = (c.lenient([LenientElement<FileName>].self, .files) ?? []).compactMap { $0.value?.name }
        // The server's sanitizeChats() already drops non-object entries; skip any bad one here too.
        chats = (c.lenient([LenientElement<ChatMeta>].self, .chats) ?? []).compactMap(\.value)
        createdAt = c.millisecondsDate(.createdAt)
        updatedAt = c.millisecondsDate(.updatedAt)
    }
}

/// Chat metadata (apps/web/src/types.ts `ChatMeta`; free chats are normalised in
/// routes/chat-lists.cjs `POST /api/freechats`).
public struct ChatMeta: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let projectId: String?
    public let updatedAt: Date?
    public let preview: String?
    public let pinned: Bool
    public let archived: Bool
    /// `cowork` for a Cowork session; absent means Chat. (`cowork` is a frozen identifier.)
    public let mode: String?

    enum CodingKeys: String, CodingKey { case id, title, projectId, updatedAt, preview, pinned, archived, mode }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(String.self, .title) ?? "New chat"
        projectId = c.lenient(String.self, .projectId)
        updatedAt = c.millisecondsDate(.updatedAt)
        preview = c.lenient(String.self, .preview)
        pinned = c.lenient(Bool.self, .pinned) ?? false
        archived = c.lenient(Bool.self, .archived) ?? false
        mode = c.lenient(String.self, .mode)
    }
}

/// Decodes an array element, or nil when that one element is malformed.
struct LenientElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// The server stores `Date.now()` milliseconds as JSON numbers.
    func millisecondsDate(_ key: Key) -> Date? {
        lenient(Double.self, key).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
