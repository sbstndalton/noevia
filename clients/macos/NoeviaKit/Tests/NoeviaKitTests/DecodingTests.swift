import Foundation
import Testing
@testable import NoeviaKit

@Suite("Decoding the core's real response shapes")
struct DecodingTests {
    @Test("GET /api/workspace (routes/chat-lists.cjs) decodes the owner's projects and free chats")
    func workspace() throws {
        let workspace = try JSONDecoder().decode(Workspace.self, from: Fixture.data("workspace__routes-chat-lists.cjs.json"))

        // The route already removed the Diary and chat-attachment projects and the bare-string chat.
        #expect(workspace.projects.map(\.id) == ["proj-1790000000000-abc123", "proj-legacy"])

        let project = workspace.projects[0]
        #expect(project.name == "Synthetic research")
        #expect(project.goal == "A synthetic goal")
        #expect(project.icon == "book")
        #expect(project.color == "#3a6ea5")
        #expect(project.pinned)
        #expect(!project.archived)
        #expect(project.model == "synthetic-model")
        #expect(project.provider == nil)
        #expect(project.routing == "auto")
        #expect(project.modes == ["chat", "code"])
        #expect(project.toolboxes == ["core"])
        #expect(project.fileNames == ["notes.md"])
        #expect(project.createdAt == Date(timeIntervalSince1970: 1_789_913_600))
        #expect(project.updatedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(project.chats.map(\.id) == ["chat-a", "chat-b"])
        #expect(project.chats[0].title == "First question")
        #expect(project.chats[0].pinned)
        #expect(project.chats[0].updatedAt == Date(timeIntervalSince1970: 1_789_999_995))
        // A meta with only an id (as sanitizeChats lets through) gets the SPA's default title.
        #expect(project.chats[1].title == "New chat")
        #expect(project.chats[1].updatedAt == nil)

        let legacy = workspace.projects[1]
        #expect(legacy.modes == ["chat"], "server migrates older projects to ['chat']")
        #expect(legacy.createdAt == nil)
        #expect(legacy.chats.isEmpty)

        #expect(workspace.freeChats.map(\.id) == ["free-1", "free-2"])
        #expect(workspace.freeChats[1].mode == "cowork")
        #expect(workspace.freeChats[1].archived)
    }

    @Test("GET /api/auth/session (routes/auth.cjs) and sign-in (auth.cjs) decode publicUser()")
    func sessionAndLogin() throws {
        let session = try JSONDecoder().decode(SessionResponse.self, from: Fixture.data("auth-session__routes-auth.cjs.json"))
        #expect(session.user.id == "7b0c2f6e-1111-4a4a-9c9c-000000000001")
        #expect(session.user.role == "member")
        #expect(session.user.onboarded)
        #expect(session.csrfToken == "synthetic-csrf-token")
        #expect(session.legacy == false)

        let login = try JSONDecoder().decode(LoginResponse.self, from: Fixture.data("auth-login-password__auth.cjs-passwordLogin.json"))
        #expect(login.user == session.user)
        #expect(login.csrfToken == "synthetic-csrf-token")
    }

    @Test("GET /api/ready (routes/health.cjs) decodes both readiness states")
    func ready() throws {
        let ready = try JSONDecoder().decode(ReadyResponse.self, from: Fixture.data("api-ready__routes-health.cjs.json"))
        #expect(ready.ready && ready.version == "0123abc")
        let starting = try JSONDecoder().decode(ReadyResponse.self, from: Fixture.data("api-ready-starting__routes-health.cjs.json"))
        #expect(!starting.ready)
    }

    @Test("Error bodies from http.cjs and the CSRF gate decode to their messages")
    func errorBodies() {
        #expect(NoeviaClient.errorMessage(Fixture.data("error-unauthorized__http.cjs.json")) == "unauthorized")
        #expect(NoeviaClient.errorMessage(Fixture.data("error-csrf__index.cjs.json")) == "invalid CSRF token")
        #expect(NoeviaClient.statusError(403, Fixture.data("error-csrf__index.cjs.json")) == .forbidden("invalid CSRF token"))
    }

    @Test("Additive v1 fields are ignored and one malformed chat does not hide the workspace")
    func lenientDecoding() throws {
        let body = #"""
        {"projects":[{"id":"p1","name":"P","futureField":{"x":1},"pinned":"yes",
          "chats":[{"id":"ok","title":"Fine"},{"title":"no id"},{"id":"c2","updatedAt":"not a number"}]}],
         "freeChats":[],"anotherFutureField":true}
        """#
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(body.utf8))
        let project = try #require(workspace.projects.first)
        #expect(!project.pinned)
        #expect(project.chats.map(\.id) == ["ok", "c2"])
        #expect(project.chats[1].updatedAt == nil)
    }

    @Test("A project without an id is a contract break and fails loudly")
    func missingIdFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Workspace.self, from: Data(#"{"projects":[{"name":"x"}]}"#.utf8))
        }
    }
}
