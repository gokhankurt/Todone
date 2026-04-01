# Todone.

**Because done feels good.**

A minimal, native macOS todo app with a monospace aesthetic. No Electron, no web views — just SwiftUI.

---

### Features

- **Two sections** — Weekly and Backlog, collapsible with a click
- **Inline editing** — click any task to edit it directly
- **Check it off** — animated strikethrough that sweeps across the text
- **Move between sections** — hover to reveal arrow icons (↑ to Weekly, ↓ to Backlog)
- **Delete on hover** — trash icon appears when you need it, hidden when you don't
- **Completed tasks** — collapse into a tidy group you can expand anytime
- **Calendar week** — shown next to the Weekly header so you always know where you are
- **Markdown persistence** — saved to `~/Documents/TodoApp/todos.md`, human-readable and editable
- **Retro splash screen** — ASCII scramble reveal on launch

### The todo file

All your tasks live in a plain markdown file:

```
~/Documents/TodoApp/todos.md
```

```markdown
## TODOs - Weekly

- [ ] Design review with team
- [x] Ship feature branch
- [ ] Update dependencies

## TODOs - Backlog

- [ ] Write onboarding docs
- [ ] Refactor auth module
```

Edit it in any text editor. The app reads and writes standard markdown checkboxes.

### Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+

### Build & Run

Open `Package.swift` in Xcode and hit Run. Or from the terminal:

```bash
swift build
open .build/debug/Todone
```

### Project Structure

```
Sources/
  TodoApp.swift       App entry point, window config, splash routing
  ContentView.swift   All views — sections, todo rows, add task, completed group
  TodoStore.swift     Data model, markdown parser, file persistence
  SplashView.swift    Retro ASCII scramble launch animation
```

### License

MIT
