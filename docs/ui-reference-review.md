# Sidebar and settings reference review

Reviewed 2026-09-10 in the authenticated ChatGPT browser UI, alongside the
existing visual direction from `ui mockups/inspiration`. This is a design audit,
not an implementation change. The desktop application itself was not inspected.
No messages were sent, project metadata changed, or account controls applied.

## Project identity

The project-name field includes a clickable icon. Its anchored popover contains
8 preset color choices (including the theme-aware default), an expandable custom
color section with a color area, hue slider and hex input, then 30 outline icons
in a six-column grid. Selection uses a restrained rounded highlight. The color
belongs to the icon rather than filling the whole project row. The same identity
appears in the sidebar and project settings. Creation exposes the picker too.

For noevia, add a small curated SVG set through the existing icon system, with
persisted project icon and color metadata. Keep older projects working with a
folder/default color. Use the same renderer in sidebar, project library and
project header. Validate persisted values on the server; do not accept arbitrary
SVG markup. Preserve distinct hover, selected and keyboard-focus states.

## Sidebar behavior

The reference separates top-level destinations, Pinned, Projects and Chats.
Section headings collapse their contents. Project rows expand nested chats;
opening the project home is a separate action. Overflow menus group Share,
Rename, Settings and Home above a divider, with pinning and destructive actions
below. Rename uses an inline title field. Icons and titles keep a consistent
baseline, while secondary row actions appear only when needed.

The collapsed rail keeps New chat, Images, Search, Pinned, Recents and the account
menu accessible. Pinned opens a compact popover. A Show more row limits long
project lists. Organize chats offers a single list or grouping by project.
Search opens a focused overlay with recent results and a dedicated close action.
The footer anchors account navigation independently of the scrolling history.

Useful next steps for noevia:

1. Add project identity selection to creation and project settings.
2. Make project expansion and project-home navigation explicit, preserving an
   obvious direct way to open a project on touch screens.
3. Normalize menu widths, padding, SVG size, row height, dividers, focus states
   and placement. Avoid permanent delete buttons in library cards.
4. Keep pinned projects and search accessible from a collapsed sidebar.
5. Use short opacity/position transitions for menus and disclosure expansion,
   with reduced-motion support. Implement after the interaction structure is stable.

## Settings

All 17 categories were opened: General, Notifications, Personalization, Plugins,
Voice, Billing, Usage, Analytics, Data controls, Cloud browser, Storage, Safety,
Security and login, Parental controls, Trusted contact, Account and Keyboard.

The main pattern is a contained modal with independently scrolling category and
content columns. Category search sits above the navigation. Rows use quiet
separators, left-aligned labels and descriptions, and right-aligned controls.
Settings with additional detail open a nested surface rather than expanding every
option on the initial page. Destructive and account-level controls are separated
from ordinary preferences. Keyboard settings pair each action with its shortcut.

Apply the row hierarchy and shared control styling to noevia's existing settings.
Retain noevia's Personal/Administration split and actual functionality. Do not
create billing, family, voice or other placeholder categories just to match the
reference. Keep the current panel error boundary and retryable data-load states.

## Other navigation reviewed

Opened Images, Library, Scheduled, Customize, the More menu, Sites, GPTs,
Finances and Health entry points. Library's filter chips, grid/list switch and
quiet metadata columns are useful for noevia's sources. Customize demonstrates
separate installed and discoverable sections; it is not a reason to expose
unimplemented integrations. Also inspected the account menu, Help submenu and
Download apps menu. Repeated project/chat rows were treated as instances of the
same controls. Purchase, logout, sharing, deletion and settings mutations were
not executed; existing conversations were not opened.

## Implemented in noevia

The follow-up adds 18 curated project icons, preset/custom colors, durable project
metadata, collapsible project groups and nested chats, a desktop rail with search
and pinned shortcuts, library options menus, keyboard navigation, subtle menu
motion, and settings row refinements. Verified locally with synthetic data across
375/768/1440 widths in both modes, including cancel/save/reload, a failed save and
retry, menu Escape/focus, delete cancellation, all settings panels, and full tool
approval arguments. No ChatGPT feature placeholders were added.
