# Architecture map

Native SwiftUI/AppKit app, macOS 14+ deployment target. Swift Package Manager builds
`StudyTable` (the historical internal name), `StudyTableCore` and `BuildScriptureIndex`.
No web service is required for core functionality.

| Area | Starting points |
|---|---|
| App and windows | Sources/StudyTable/StudyTableApp.swift, MainView.swift |
| State and preferences | AppState.swift, SavedLayouts.swift |
| Detached pane windows and live notebook session | DetachedWindows.swift, NotebookSession.swift; shared AppState/StudyStore, no copied notes database |
| Reader and study panes | Panes.swift, ReadingNavigation.swift, Models.swift |
| Guided passage learning | GuidedStudyView.swift, GrammarLessons.swift, GrammarHelpView.swift, PassageLearning.swift |
| Appearance | Theme.swift, native pane/control components |
| Bible search | BibleSearch.swift, BibleSearchSession.swift, BibleSearchView.swift |
| Resources | ResourceCatalog.swift, ResourceDiscovery.swift, ResourceBooks.swift |
| Scripture formats | Sources/StudyTableCore; scripts/build-scripture-packs.sh |
| Profiles and reception | FatherProfileStore.swift, FatherProfileViews.swift, patristic reader stores/views |
| AI and CLI | AIAssistant.swift, AIAssistantView.swift, LocalAIModels.swift, LocalAIManager.swift, LecternCLI.swift |
| Resource generation | scripts/build-*.py and source/provenance notices |
| Tests | Tests/StudyTableTests; TestSupport.swift injects temporary stores |

Use `rg --files Sources` to locate a feature; names above are orientation, not an API.
Offline snapshots are copied into the Swift resource bundle. `AppResources` resolves
both packaged and SwiftPM layouts. Personal study data is outside the app bundle;
never treat it as a test fixture. Public snapshots have an explicit hash manifest.

Publisher APIs use reader-supplied Keychain credentials. Local AI uses a pinned
llama.cpp helper on authenticated loopback with a sanitized environment and a parent
watcher. Downloads are verified before installation. AI gets only explicit chat and
attached context, cannot execute tools, and has no automatic cloud fallback.

Prefer small changes through existing services and injected stores. Keep source text,
editorial claims, author profiles and reader-selected alignment lenses separate.
