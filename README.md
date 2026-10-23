# Dispaces

Manage macOS Spaces (Desktops): a small floating bar for macOS 26 and 27 that shows the Spaces of every display, highlights the current one, lets you name displays and Spaces, and switches Space when you click a tile.

```
 STUDIO DISPLAY [1 HOME][2 MUSIC][3 TECH][4 MAIL] │ MACBOOK PRO [5 CHAT][6 NOTES][FS Safari]
```

- No network access, no third-party code, no auto-update.
- Needs one permission: Accessibility (to press your own "Switch to Desktop N" shortcuts).
- The built app is called `SpacesBar.app` (bundle ID `io.github.kosrodka.SpacesBar`).

| Doc | |
|---|---|
| [Requirements](docs/01-requirements.md) | What it does and why it isn't a WidgetKit widget |
| [Architecture](docs/02-architecture.md) | Technology choices and design |
| [UI and UX](docs/03-ui-ux.md) | Look and interactions |
| [Security](docs/04-security.md) | Threat model, controls, pen-test plan |
| [CI/CD](docs/05-ci-cd.md) | Repository, pipelines, releases |
| [Operations](docs/06-operations.md) | Install, set up, update, troubleshoot, uninstall, pen tests |
| [Pen-test report](docs/07-pen-test-report.md) | Results |
| [User manual](docs/08-user-manual.md) | How to use the app (also in the app: menu bar icon › Help › User manual) |

Quick build (macOS 26+, Xcode 26):
```sh
swift test && scripts/bundle.sh 0.1.0 && scripts/security-check.sh
cp -R build/SpacesBar.app /Applications/ && open /Applications/SpacesBar.app
```

Full install steps, including downloading a release instead of building: [Operations §6.1](docs/06-operations.md).

## License

[MIT](LICENSE). Copyright 2026 Kamil (kosrodka).
