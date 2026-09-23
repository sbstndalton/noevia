# Return 400 for malformed project and Diary JSON

Implemented for review; not merged or deployed. Issues: [#4](https://github.com/sbstndalton/noevia/issues/4).

The bounded JSON reader now reports `400 invalid JSON` and accepts an optional size limit. Background upload/document/sync requests, Diary local exchanges, and authenticated Diary connector requests use it before starting work. Local exchanges parse once and forward canonical JSON. Existing upload limits and 413 responses remain intact.

Validation: 1,249 web tests pass; typecheck, production build, and design lint pass. Focused tests cover all five malformed-body paths, absence of dispatch/fetch/audit side effects, valid requests, and bounded parsing. All data and service calls are synthetic.
