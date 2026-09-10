# Claude live Diary plugin

A dependency-free Python stdio MCP plugin for Claude. Tools read/write the live
noevia Diary through its existing versioned companion API. It is not a public
unauthenticated MCP URL. The plugin requires Python 3 and outbound HTTPS to noevia.
Keep approval enabled for `diary_write`; no noevia write-approval policy is changed.

After deployment, an administrator can mint a dedicated revocable credential:

```sh
# Redirect output into a private file OUTSIDE the repository and synced folders.
ssh root@10.69.0.130 'docker exec cowork-web-1 node server/diary-connector-admin.cjs create USERNAME "Claude Diary"' > /private/plugin/connection.json
chmod 600 /private/plugin/connection.json
```

Place the private connection.json beside server.py in an installed copy of this
plugin. Never commit it or distribute a credential-bearing plugin to another user.
Import that plugin through Claude's plugin UI. A desktop stdio setup may also run
server.py with `NOEVIA_DIARY_CONFIG` pointing at the private connection file; do not
assume desktop config automatically enables it in Cowork. The plugin skill directs
Diary work to the live tools instead of the synced folder.

Revoke immediately if needed:

```sh
ssh root@10.69.0.130 'docker exec cowork-web-1 node server/diary-connector-admin.cjs list USERNAME'
ssh root@10.69.0.130 'docker exec cowork-web-1 node server/diary-connector-admin.cjs revoke USERNAME CONNECTOR_ID'
```

Signed-in users can also list/create/revoke their own credentials through
`/api/profile/diary-connectors` (GET/POST) and `/api/profile/diary-connectors/ID`
(DELETE), with normal session and CSRF protection. Credentials authorize only
Markdown list/read/versioned-write operations within that user's enabled Diary;
no project, account, storage-credential or general Nextcloud access.

Existing Mac-only edits are not automatically merged. Compare them before switching
writers. Whole-file saves require the prior version and never automatically retry;
semantic append/idempotent operation recovery remains future work.
