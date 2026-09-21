# Claude live Diary plugin

A dependency-free Python stdio MCP plugin for Claude. Tools read/write the live
noevia Diary through its existing versioned companion API. It is not a public
unauthenticated MCP URL. The plugin requires Python 3 and outbound HTTPS to noevia.
Keep approval enabled for `diary_write`; no noevia write-approval policy is changed.

A connection is made in noevia itself: Settings → Diary & storage → Connected apps.
Name it (for example "Claude Diary"), copy the credential JSON once, and save it as
`connection.json` in a private folder OUTSIDE the repository and synced folders
(`chmod 600`). The same screen revokes it in one click.

Place the private connection.json beside server.py in an installed copy of this
plugin. Never commit it or distribute a credential-bearing plugin to another user.
Import that plugin through Claude's plugin UI. A desktop stdio setup may also run
server.py with `NOEVIA_DIARY_CONFIG` pointing at the private connection file; do not
assume desktop config automatically enables it in Cowork. The plugin skill directs
Diary work to the live tools instead of the synced folder.

Revoke immediately if needed: sign in to noevia, open Settings → Diary & storage →
Connected apps, and click Revoke next to the connection. The credential stops working
at once; the plugin's next call answers 401 until a new connection is made and saved.
There is no server-side script for this any more (`server/diary-connector-admin.cjs`
was removed); an administrator who cannot sign in as that account can disable the
account under Settings → Users, which makes every credential it holds stop verifying.

Signed-in users can also list/create/revoke their own credentials through
`/api/profile/diary-connectors` (GET/POST) and `/api/profile/diary-connectors/ID`
(DELETE), with normal session and CSRF protection. Credentials authorize only
Markdown list/read/versioned-write operations within that user's enabled Diary;
no project, account, storage-credential or general Nextcloud access.

Existing Mac-only edits are not automatically merged. Compare them before switching
writers. Whole-file saves require the prior version and never automatically retry;
semantic append/idempotent operation recovery remains future work.


## Installed-package verification — 2026-09-13

The existing private installed server.py matches this repository byte-for-byte.
An actual stdio process passed initialize, initialized notification, tools/list
and ping using the installed configuration; no Diary tool was called and no
credential/content was printed. Three bridge unit tests pass. This proves local
bootstrap only: Claude plugin import/enablement and a synthetic client comparison
remain pending. Do not treat a desktop configuration file as proof of Cowork use.
