# Master Prompt — UI Architecture + Design System Implementation

> Written by the user, 2026-09-18. Planned as roadmap phase "UI overhaul (2026-09-18 brief)";
> see `roadmap.md`. It supersedes the visual direction in `design-system.md` and
> `spec-ui-direction.md` wherever they disagree.

You are an elite front-end engineer and UI systems architect.

Your task is to build/refine the application UI by combining:

1. the **information architecture, controls, layouts, feature placement, menus, panels, interaction patterns, and organization** shown in the supplied UI screenshots and their written descriptions; and
2. a new visual design language derived from **Apple HIG, Material 3, Ramps Studio, Liquid Glass, Aero/UniFi-style structural panes, and the Impeccable coding-agent skill**.

This is not a generic dashboard exercise.

The screenshots/descriptions define **what the application contains and how it is organized**.

The external design references define **how that architecture should look, feel, move, layer, and communicate state**.

Do not discard the screenshot-derived architecture just because the external visual references use different example applications.

**The current noevia visual design is not a reference. Preserve its functionality, data flows and tests; replace its visual language entirely.**

---

# 1. Required Local UI Reference Material

The UI screenshots, descriptions, merged Markdown reference, and related inspiration material are located here:

`/Users/sebastiandalton/Library/CloudStorage/Nextcloud-drive.daserver.work-SebastianDalton/Documents/ai-agentic-folder/Projects/Docker App Projects/AI frontend thing/ui mockups/inspiration`

Before substantial implementation:

1. Inspect this directory.
2. Read the merged image-description Markdown file completely.
3. Inspect the actual screenshots/images where available.
4. Compare the written descriptions against the screenshots when useful.
5. Build an internal inventory of:
   - navigation patterns
   - page types
   - card types
   - sidebars
   - contextual panes
   - menus
   - modals
   - settings structures
   - project/workspace organization
   - composers
   - permission controls
   - Skills / Plugins / Connectors
   - activity/usage views
   - model controls
   - status indicators
   - project and chat actions
6. Treat those references as the architectural basis for the application.

Do not skim only a few screenshots and extrapolate the rest.

Do not replace the supplied interface patterns with a generic SaaS dashboard.

---

# 2. Source-of-Truth Hierarchy

When references overlap or disagree, use this priority system.

## Level 1 — Supplied screenshots and merged descriptions

These define:

- application information architecture
- feature placement
- navigation hierarchy
- page organization
- sidebar organization
- project/workspace behavior
- cards and list structures
- settings organization
- composers
- contextual right-side panels
- modals
- menus
- controls
- Skills / Plugins / Connectors architecture
- permission workflows
- activity/usage layouts
- outputs/artifacts
- memory/context organization
- model controls
- source folders
- local/remote state
- status indicators
- project actions
- chat/task actions

They define the **anatomy of the product**.

They do **not** need to determine the final visual styling.

## Level 2 — Apple Human Interface Guidelines

Apple HIG is the primary authority for:

- readability
- hierarchy
- typography
- spacing discipline
- interaction quality
- motion
- animation purpose
- focus behavior
- control sizing
- accessibility
- reduced-motion behavior
- visual layering
- affordances
- responsiveness
- feedback
- consistency

Reference:

https://developer.apple.com/design/human-interface-guidelines

Do not blindly clone macOS controls.

Use HIG principles to give the custom interface the clarity, polish, responsiveness, and interaction discipline of a high-quality native application.

## Level 3 — Material 3 + Ramps Studio

Material 3 defines the **semantic color logic**.

Reference:

https://m3.material.io

Ramps Studio defines much of the **palette personality, atmospheric color character, tonal sophistication, and chromatic direction**.

Reference:

https://www.ramps.studio

Use both.

Material 3 determines how colors function.

Ramps helps determine what those colors feel like.

## Level 4 — Surface/material references

Use these references for the physical treatment of interface surfaces:

### Structural / flatter panes
- Windows Aero design principles
- Ubiquiti UniFi-style interface treatment

### Liquid / refractive foreground surfaces
- https://github.com/nikdelvin/liquid-glass
- https://freefrontend.com/css-liquid-glass/#google_vignette
- https://aethercss.lovable.app
- https://github.com/zoxilsi/studio

Use these selectively according to the material hierarchy described below.

## Level 5 — Impeccable

Impeccable is an implementation and critique skill.

Reference:

https://github.com/pbakaus/impeccable

It improves execution quality but does not override the architecture or design authorities above.

---

# 3. Required Coding-Agent Skill — Impeccable

Before substantial UI implementation, acquire and use **Impeccable**:

https://github.com/pbakaus/impeccable

Treat Impeccable as an active coding-agent skill, not merely a visual reference.

If it is not already installed:

1. Inspect the repository.
2. Determine how the current agent environment supports reusable skills, prompts, instructions, or agent extensions.
3. If direct skill installation is supported, download/install it.
4. If the environment uses repository-local skills, place/adapt it appropriately.
5. If the current agent cannot directly install third-party skills, recreate/adapt the relevant Impeccable skill instructions into the agent's supported skill format.
6. Preserve its actual workflow and intent rather than reducing it to a few generic design tips.
7. Use the skill during implementation.
8. Use it again for a final UI critique before declaring the work complete.
9. Fix legitimate issues identified by that review.

Do not silently skip Impeccable because it is unavailable by default.

Do not merely read the README and claim that this is equivalent to using the skill if a real skill mechanism is available.

Impeccable does not override:

- screenshot-derived architecture
- Apple HIG
- Material 3 color roles
- Ramps palette direction
- the surface/material hierarchy
- explicit project requirements

---

# 4. UI Architecture Requirements

Derive the application's structure from the supplied screenshots/descriptions.

## Persistent application sidebar

Implement a persistent primary sidebar comparable to the supplied Claude, Codex, ChatGPT, Cowork, and noevia references.

It should support appropriate combinations of:

### Primary navigation
- New
- Projects
- Artifacts / Outputs
- Scheduled
- Plugins
- Explore
- Customize
- other application-specific primary areas

### Project/workspace section
- project icon
- project name
- selected state
- pin state
- expandable child chats/tasks where applicable
- add-project action
- search
- filtering
- section/category organization

### Chat/task section
- recent chats
- project chats
- task state
- current selection
- optional metadata

### Bottom utility area
- account/avatar
- plan
- appearance/design
- connection status
- inference status
- local/remote state
- utility actions

Do not place every feature into one undifferentiated navigation list.

Use clear visual grouping.

---

# 5. Project / Workspace Architecture

Project pages should support the patterns documented in the references.

Potential elements include:

- breadcrumb or project path
- project title
- project icon
- description
- pin action
- overflow action menu
- project composer
- outputs/artifacts
- recent chats/tasks
- project instructions
- memory
- context folders
- source folders
- scheduled tasks
- local/remote indicators
- file references
- project-specific metadata

Project actions should support appropriate combinations of:

- pin / unpin
- edit
- rename
- archive chats
- remove project
- reveal in Finder / local filesystem where relevant
- move to section
- assign category
- source-folder management
- local-project association

Use the references to determine which actions belong where.

---

# 6. Project Cards

Use project cards similar in information density to the screenshot references.

Cards may contain:

- icon
- title
- description
- pin state
- last-updated time
- chat/task count
- local/remote status
- source/context indicator

Desktop layouts may use sparse two-column grids.

Narrow layouts should collapse to one column.

Do not turn project cards into oversized marketing cards.

Leave meaningful negative space.

---

# 7. Main Workspace Canvas

The main workspace should feel calm, spacious, and deliberate.

Do not fill empty space simply because space exists.

The references repeatedly use:

- large quiet canvases
- compact content clusters
- restrained cards
- contextual secondary panes
- focused primary interaction surfaces

Preserve that character.

Avoid generic enterprise dashboard density.

---

# 8. Composer Architecture

The composer is a primary interaction surface.

Depending on context, support:

- attachment/add button
- project context
- folder context
- local/remote context
- approval mode
- model selector
- reasoning/effort selector
- microphone
- voice
- send/run
- active task state
- optional context chips

Keep the text-entry surface visually dominant.

Model and execution controls should remain secondary.

When working inside a project, show project context clearly.

---

# 9. Contextual Right-Side Panels

Use optional contextual panels based on the supplied references.

Possible panel content:

- Instructions
- Memory
- Context
- Source folders
- Scheduled
- Files
- Changes
- Terminal
- Progress
- Outputs
- document preview
- connector details
- task status

These panels should appear because the workflow calls for them.

Do not permanently reserve a right sidebar on every page if no secondary context exists.

On narrower screens, convert these panels into drawers, sheets, or stacked content.

---

# 10. Skills, Plugins, and Connectors

Treat **Skills**, **Plugins**, and **Connectors** as related but distinct concepts.

## Skills

Support:

- Your skills / Discover
- search
- filter
- sorting
- source/publisher
- category
- description
- install/add state
- last-edited metadata where appropriate
- featured skills
- marketplace discovery

## Plugins

Support:

- Your plugins / Discover
- search
- filter
- sorting
- publisher
- install count
- descriptions
- featured banners
- add/install controls
- optional workspace/folder scope

## Connectors

Support:

- Your connectors / Discover
- search
- filter
- connector cards
- connected state
- add state
- verification/source indicator
- connector detail pages
- disconnect
- overflow actions
- prompt suggestions

Connector detail pages should include tool permissions.

### Permission groups

At minimum support the architecture demonstrated in the references:

- read-only tools
- write/delete tools

Permission states:

- Always allow
- Needs approval
- Blocked

Where appropriate, each tool should have its own three-way permission control.

Group-level controls may set defaults.

Do not reduce connectors to a simple OAuth list.

---

# 11. Settings Architecture

Use a persistent grouped settings sidebar.

Possible groups based on the references:

## Settings / Personal
- General
- Account
- Privacy
- Billing
- Usage
- Capabilities
- Memory
- Profile
- Appearance
- Voice
- Personalization
- Analytics

## Desktop / Integrations
- General
- Extensions
- Developer
- Computer use
- Browser
- Plugins
- Connectors

## Coding
- Hooks
- Connections
- Git
- Environments
- Worktrees
- model/routing configuration

## Customize
- Skills
- Connectors
- Plugins

Individual settings rows should generally follow:

**label**  
supporting description                 **control**

Controls may include:

- toggle
- dropdown
- segmented selector
- button
- text field
- three-state permission control
- slider
- file/folder picker

Avoid a giant undifferentiated settings page.

---

# 12. Analytics and Activity

When analytics are present, follow the patterns from the screenshots rather than inventing unrelated business metrics.

Useful patterns include:

- sessions
- messages
- total tokens
- input/output tokens
- cached tokens
- active days
- current streak
- longest streak
- peak hour
- favorite model
- plan usage
- credit usage
- model usage
- plugin/tool calls
- skills used
- yearly contribution heatmap
- inference metrics

Do not introduce:

- sales KPIs
- revenue cards
- generic enterprise charts
- CRM metrics
- meaningless dashboard filler

unless the actual application requires them.

---

# 13. Modal and Menu Patterns

Use centered modals for bounded configuration tasks such as:

- create project
- edit project
- project icon selection
- source-folder configuration
- custom connector setup
- connector permissions
- destructive confirmation
- import/add flows

Modal hierarchy:

1. title
2. description where needed
3. primary content/form
4. secondary/destructive action
5. cancel
6. primary action

Popup/context menus should remain compact.

Use the screenshot references for menu organization such as:

- Pin / Unpin
- Edit
- Rename
- Section
- Reveal in Finder
- Archive
- Remove
- Share
- Copy
- Continue in
- Open in new window

Do not transform simple context menus into giant floating cards.

---

# 14. Apple HIG — Styling, Readability and Interaction

Use current Apple HIG principles as the main behavioral/styling discipline.

## Typography

Use a clean, highly readable UI typography system.

Maintain clear levels for:

- page title
- section heading
- control label
- body copy
- helper text
- metadata
- status text

Do not use oversized marketing typography inside productivity interfaces.

Avoid low-contrast text over transparency.

## Spacing

Use a coherent spacing token system.

Prefer an 8pt-derived rhythm where practical:

- 4
- 8
- 12
- 16
- 24
- 32
- 40
- 48

Use tighter spacing inside related controls and more space between unrelated groups.

Do not treat every gap as identical.

## Control sizing

Ensure:

- comfortable hit targets
- keyboard access
- clear focus
- adequate spacing
- readable labels

## Motion

Follow Apple HIG principles for motion.

Do not use one universal:

`transition: all ...`

for the entire application.

Create a small motion system for:

- micro-state changes
- hover
- press
- selection
- menus
- popovers
- modals
- drawers
- sidebar transitions
- contextual panels
- page/content transitions

Motion should communicate:

- cause and effect
- spatial continuity
- hierarchy
- state change

Use spring-like behavior where appropriate.

Keep productivity interactions fast.

Honor:

`prefers-reduced-motion`

Avoid:

- decorative bouncing
- gratuitous scale animations
- excessive ambient animation
- slow cinematic transitions

---

# 15. Color System — Material 3 + Ramps Studio

Use:

https://m3.material.io

as the semantic color foundation.

Use:

https://www.ramps.studio

for chromatic character, tonal progression, palette sophistication, and atmosphere.

## Material 3 role structure

Build the theme around semantic roles such as:

- primary
- on-primary
- primary-container
- on-primary-container
- secondary
- on-secondary
- secondary-container
- tertiary
- surface
- surface-dim
- surface-bright
- surface-container-lowest
- surface-container-low
- surface-container
- surface-container-high
- surface-container-highest
- on-surface
- on-surface-variant
- outline
- outline-variant
- error
- error-container

Add application-specific semantic roles where necessary:

- success
- connected
- warning
- offline
- inference-active
- local
- remote

Do not simply copy Material's default purple palette.

Create a noevia-specific palette.

## Ramps influence

Use Ramps Studio to inform:

- tonal ramp quality
- saturation progression
- accent sophistication
- atmospheric background color
- colorful but controlled highlights
- subtle hue relationships
- depth

Material defines **what a color means**.

Ramps helps define **what that color feels like**.

## Color restraint

Use stronger chroma primarily for:

- selected navigation
- primary actions
- model/provider identity
- online/connected state
- active controls
- charts/visualization
- important status information

Keep structural surfaces more neutral.

Do not cover the entire interface in neon colors.

---

# 16. Material / Surface Hierarchy

The UI should use two major physical surface families.

Do not apply one glass effect indiscriminately to everything.

---

## A. Structural Back-Pane Surfaces — Aero / UniFi Influence

Use Aero/UniFi-inspired treatment for stable structural surfaces such as:

- application sidebar
- settings sidebar
- project navigation
- context pane
- inspector pane
- popup/menu body
- larger toolbar regions
- secondary workspace panes
- settings containers
- organizational cards

These surfaces should feel:

- stable
- architectural
- calm
- slightly dimensional
- layered
- high quality

Characteristics may include:

- translucent or semi-opaque dark/light substrate
- subtle environmental tint
- moderate backdrop blur where appropriate
- thin light-catching border
- faint inset highlight
- restrained outer shadow
- strong readability
- little or no glow
- minimal distortion

They should remain visually flatter than Liquid Glass controls.

Do not make every back pane look like a floating lens.

---

## B. Liquid Glass Foreground Layer

Use Liquid Glass selectively for interactive foreground elements.

References:

- https://github.com/nikdelvin/liquid-glass
- https://freefrontend.com/css-liquid-glass/#google_vignette
- https://aethercss.lovable.app
- https://github.com/zoxilsi/studio

Appropriate targets include:

- floating toolbar controls
- primary action buttons
- segmented controls
- active selectors
- selected chips
- floating composer controls
- model selectors
- context pills
- modal action clusters
- selected navigation capsules
- floating popovers
- temporary control surfaces

The effect should communicate that the element sits physically above the structural interface.

Where technically possible, use real optical techniques derived from the references:

- backdrop filtering
- refraction
- local distortion
- specular highlights
- edge highlights
- tint
- environmental color pickup
- subtle lensing
- layered translucency
- physical depth cues

Do not reduce Liquid Glass to:

`background: rgba(...) + blur`

if the referenced implementation supports more sophisticated optical behavior.

Inspect the source implementations.

Use graceful fallbacks where required.

Never sacrifice:

- text readability
- accessibility
- focus clarity
- performance
- hit-target clarity

Do not apply Liquid Glass to every row, card, or background pane.

---

# 17. Layering Model

Think of the interface as a physical stack.

### Layer 0 — Canvas
Base background / atmospheric environment.

### Layer 1 — Structural panes
Sidebars, primary containers, navigation panes.

Aero/UniFi-inspired.

### Layer 2 — Content surfaces
Project cards, settings groups, lists, inspectors.

Mostly restrained and relatively flat.

### Layer 3 — Interactive foreground controls
Selected chips, mode controls, floating toolbar items, important buttons.

Liquid Glass where appropriate.

### Layer 4 — Temporary overlays
Menus, popovers, modals, command palettes, permission sheets.

Strongest depth separation.

Maintain consistent z-axis logic.

Do not arbitrarily mix material treatments.

---

# 18. Geometry

Use a coherent radius system instead of random values.

Suggested hierarchy:

- compact controls → small radius
- inputs/buttons/rows → medium radius
- cards/menus → larger radius
- major panes/modals → extra-large radius
- pills/segmented controls → fully rounded where appropriate

Favor smooth, squircle-like shapes where feasible.

Do not make every component equally rounded.

Do not create giant bubbly containers without structural justification.

---

# 19. Borders and Shadows

Prefer subtle physical separation.

Use:

- thin neutral borders
- restrained highlight edges
- subtle inset reflections
- controlled shadows
- environment-aware tint

Reserve stronger shadows and optical depth for:

- floating menus
- dialogs
- popovers
- Liquid Glass controls
- active overlays

Avoid generic Tailwind shadow stacks pasted onto every component.

Avoid permanent neon glows.

---

# 20. Interaction States

Every interactive component must support relevant states:

- default
- hover
- focus-visible
- active/pressed
- selected
- disabled
- loading
- connected
- disconnected
- error
- approval-required
- destructive

State changes should be visually obvious without becoming noisy.

Keyboard navigation must work.

Focus rings must remain visible over glass/translucent backgrounds.

---

# 21. Responsive Behavior

## Desktop
- persistent main sidebar
- optional secondary/right panel
- spacious central canvas
- multi-column card layouts where appropriate

## Tablet
- narrower/collapsible sidebar
- contextual panels may collapse
- preserve composer prominence

## Mobile
- sidebar becomes drawer
- cards become single-column
- contextual panels become sheets or stacked sections
- important controls remain reachable
- composer remains accessible
- avoid desktop-width menu assumptions

Do not simply scale down the desktop UI.

Adapt the information hierarchy.

---

# 22. Implementation Quality

Use the existing project stack.

Prefer reusable design primitives and tokens.

Useful primitives may include:

- AppSidebar
- NavigationGroup
- ProjectTree
- ProjectCard
- Composer
- ContextPanel
- InspectorPanel
- SettingsSidebar
- SettingsSection
- SettingsRow
- SegmentedControl
- PermissionControl
- MarketplaceCard
- ConnectorCard
- ConnectorPermissionGroup
- Modal
- Popover
- ContextMenu
- StatusBadge
- ActivityHeatmap
- MetricCard
- GlassControl
- StructuralPane

Do not duplicate styles across one-off components.

Centralize:

- color tokens
- spacing tokens
- radius tokens
- typography
- motion
- borders
- elevation
- material treatment

---

# 23. External Reference Investigation

Do not rely only on superficial screenshots or assumptions.

Where access is available, actively inspect the source or implementation of:

- Impeccable
- zoxilsi/studio
- liquid-glass
- AetherCSS
- Ramps Studio
- Material 3 documentation
- Apple HIG documentation

Extract useful implementation approaches from:

- actual CSS
- shaders
- SVG filters
- backdrop-filter use
- component composition
- token organization
- animation logic
- responsive behavior
- accessibility handling

Do not copy irrelevant application architecture from those projects.

Their purpose here is visual/implementation guidance.

The local screenshot/descriptions remain the application-architecture authority.

---

# 24. No Generic SaaS Output

Explicitly avoid default AI-generated UI patterns such as:

- arbitrary 3×3 KPI grids
- giant gradient hero banners
- meaningless analytics cards
- random glass cards everywhere
- excessive pill buttons
- oversized headings
- overuse of neon
- random gradients
- “Welcome back” dashboards
- fake finance/business data
- meaningless charts
- decorative widgets unrelated to the actual application

Every visible component must justify its presence through:

- the supplied UI architecture
- actual application functionality
- or a clearly defined design-system purpose

---

# 25. Data and Functional Integrity

Build functional components rather than screenshot-only mockups.

Do not fabricate backend behavior.

If a referenced UI feature does not yet have backend support:

1. implement the UI architecture cleanly;
2. identify the integration boundary;
3. use existing real state where available;
4. clearly mark genuinely unavailable functionality in code/design;
5. do not create fake successful actions.

Do not destroy existing working application logic for visual convenience.

---

# 26. Existing Codebase Discipline

Before implementation:

1. inspect the repository structure;
2. read the relevant project instructions/agent files;
3. determine the actual frontend stack;
4. identify existing design tokens/components;
5. understand current routes and state management;
6. identify reusable components;
7. inspect tests;
8. understand how the app is currently deployed.

Do not start by replacing the entire UI architecture from scratch unless the repository clearly requires that.

Preserve working functionality.

Make bounded, reviewable changes.

---

# 27. Execution Workflow

Use this workflow.

## Phase 1 — Reference audit

- inspect local inspiration folder
- read merged descriptions
- inspect screenshots
- inspect external design references
- acquire/load Impeccable
- inventory existing app UI

## Phase 2 — Architecture mapping

Map the screenshot-derived patterns onto the current application.

Document internally:

- what already exists
- what should change
- what is missing
- which screenshot patterns apply to which pages

## Phase 3 — Design token system

Define:

- semantic colors
- light/dark theme roles
- spacing
- typography
- radius
- borders
- structural surfaces
- Liquid Glass surfaces
- shadows/elevation
- motion
- focus states

Do this before scattering visual constants throughout components.

## Phase 4 — Core shell

Implement/refine:

- canvas
- sidebar
- project navigation
- content pane
- contextual pane architecture
- responsive shell

## Phase 5 — Shared primitives

Implement/refine reusable:

- controls
- cards
- modal
- menus
- panes
- segmented controls
- badges
- glass controls
- settings rows
- permission controls

## Phase 6 — Feature surfaces

Apply architecture to:

- projects
- chats/tasks
- settings
- Skills
- Plugins
- Connectors
- analytics/activity
- model controls
- context/memory
- outputs/artifacts

## Phase 7 — Responsive/accessibility pass

Check:

- desktop
- tablet
- narrow/mobile
- keyboard
- focus-visible
- contrast
- reduced motion
- overflow
- long labels
- empty states
- loading states
- disabled states

## Phase 8 — Impeccable review

Run a final UI/UX critique using Impeccable.

Resolve legitimate:

- hierarchy problems
- spacing inconsistencies
- visual noise
- weak contrast
- generic component styling
- accessibility issues
- poor responsive behavior
- inconsistent interaction states

## Phase 9 — Validation

Run:

- formatter
- typecheck
- lint
- unit tests
- relevant integration/browser tests
- production build

Do not declare completion if the build or existing tests are broken.

---

# 28. Final Acceptance Criteria

The result should:

- visibly derive its layout and organization from the supplied screenshot references;
- preserve the application's real feature architecture;
- feel cohesive rather than like several unrelated design systems were pasted together;
- use Apple HIG principles for interaction quality, readability, motion, and spacing;
- use Material 3 semantic color logic;
- use Ramps Studio for palette character and atmospheric color sophistication;
- use Aero/UniFi-inspired material treatment for structural panes;
- use Liquid Glass selectively for higher-level interactive foreground surfaces;
- use Impeccable as an active implementation/review skill;
- provide strong light and dark themes if the current application supports both;
- remain readable and accessible;
- remain responsive;
- avoid generic SaaS patterns;
- preserve working functionality;
- use reusable design-system primitives;
- pass the relevant tests/build.

The final product should feel like a coherent next-generation AI workspace rather than a clone of Claude, ChatGPT, Codex, Windows Aero, Material Design, or macOS.

The screenshot references provide the **product anatomy**.

Apple HIG provides the **interaction discipline**.

Material 3 provides the **semantic color logic**.

Ramps Studio provides the **chromatic personality**.

Aero/UniFi provides the **structural pane language**.

Liquid Glass provides the **foreground physical material layer**.

Impeccable provides the **implementation and critique discipline**.

Combine them intentionally rather than averaging them together.
