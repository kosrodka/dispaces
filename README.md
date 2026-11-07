# Dispaces

Manage macOS Spaces (Desktops): a row of small square tiles in the macOS menu bar (macOS 26 and 27), one per Space and grouped by display, with the current one highlighted. Click a tile to switch Space; name displays and Spaces. When macOS hides the menu bar item, a small floating bar stands in.

```
 [1][2][3][4]   [5][6][FS]   🔋  Wi-Fi  Sat 7 Nov 17:20
```

- No network access, no third-party code, no auto-update.
- Needs one permission: Accessibility (to press your own "Switch to Desktop N" shortcuts).
- The built app is called `Dispaces.app` (bundle ID `io.github.kosrodka.SpacesBar`, kept unchanged so settings carry over).

| Doc | |
|---|---|
| [Requirements](docs/01-requirements.md) | What it does and why it isn't a WidgetKit widget |
| [Architecture](docs/02-architecture.md) | Technology choices and design |
| [UI and UX](docs/03-ui-ux.md) | Look and interactions |
| [Security](docs/04-security.md) | Threat model, controls, pen-test plan |
| [CI/CD](docs/05-ci-cd.md) | Repository, pipelines, releases |
| [Operations](docs/06-operations.md) | Install, set up, update, troubleshoot, uninstall, pen tests |
| [Pen-test report](docs/07-pen-test-report.md) | Results |
| [User manual](docs/08-user-manual.md) | How to use the app (also in the app: right-click the tiles › Help › User manual) |

Quick build (macOS 26+, Xcode 26):
```sh
swift test && scripts/bundle.sh 0.1.0 && scripts/security-check.sh
cp -R build/Dispaces.app /Applications/ && open /Applications/Dispaces.app
```

Full install steps, including downloading a release instead of building: [Operations §6.1](docs/06-operations.md).

## License

[MIT](LICENSE). Copyright 2026 Kamil Ośródka (github.com/kosrodka).
