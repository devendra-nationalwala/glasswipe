# Glasswipe

Native macOS cleaner (Swift + SwiftUI, Liquid Glass, macOS 26+). Planning is tracked as a wayfinder map in GitHub Issues.

## Working rules

- **Keep the docs current.** `README.md` is for people who install and use the app (download, install, usage, safety, FAQ, disclaimer); `CONTRIBUTING.md` is for building, testing, layout and contribution rules. Update whichever a change affects, in the same change, so anyone forking the repo can follow it.
- **Screenshots:** regenerate with `open -n build/Glasswipe.app --args --demo --snapshot=build/shots`, then resize into `docs/screenshots/` (`sips -Z 1600`). Demo mode shows only made-up apps, files and system figures; never commit screenshots of real machine data.
- **Commits and PRs:** plain, descriptive messages. No co-author trailers or tool attribution lines.
- Use the vocabulary in `GLOSSARY.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `devendra-nationalwala/glasswipe`, managed with `gh`. If your default `gh` login is a different account, set `GH_TOKEN` to a token for the repo owner's account. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the root, ADRs in `docs/adr/`. See `docs/agents/domain.md`.
