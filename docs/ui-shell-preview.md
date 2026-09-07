# Navigation, settings, and coding interface preview

This release adds a cleaner sidebar with project/chat search, a Chat/Code switch, and an account popover. Settings opens a large searchable dialog with independent category navigation, keyboard dismissal, and light/dark appearance choices.

Existing profile, authentication, providers, model routing, service health, and diary/storage controls retain their existing behavior. The ordinary workspace stays mounted while hidden in coding mode, preserving a temporary local diary session.

Coding mode has separate navigation and empty project/task areas, an activity grid, a draft composer, and a collapsible workspace panel. It does not read repositories, run commands, call a coding model, or modify files. Its draft is temporary and resets when leaving coding mode.

Scheduled tasks, plugins, integrations, privacy options, billing, usage tracking, and additional coding settings are clearly marked UI previews with disabled controls. No new backend endpoints, dependencies, credentials, or permissions are introduced. Activity values are empty, not simulated usage.

Validation: TypeScript check, production Vite build, 70 existing web tests, and browser checks for mode switching, account popup, settings dismissal, themes, and mobile layout.
