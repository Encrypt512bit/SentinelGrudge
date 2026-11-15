# Sentinel Grudge

Sentinel Grudge is a World of Warcraft addon for WoW Forever (interface 16001) by [Encrypt512bit](https://github.com/Encrypt512bit). It extends the Sentinel PvP addon (folder `ForeverPvPIntel`) with an attacker history, Friendly and KOS tags, an on-screen KOS warning, a minimap button, and automatic removal of a Friendly tag when that player attacks you.

Version 1.2.0. Slash command: `/grudge` (`/sgrudge` is an alias).

## Requirements

- WoW Forever, interface 16001.
- Sentinel PvP, installed as the addon folder `ForeverPvPIntel`.

Sentinel Grudge reads `ForeverPvPIntelDB` (per character). Its own tags, guild cache, settings, and warning position live in `SentinelGrudgeDB` (account-wide). The toc lists the dependency:

```
## Dependencies: ForeverPvPIntel
```

## Install

Copy the `SentinelGrudge` folder into `_forever_\Interface\AddOns`, then `/reload`.

```
_forever_\Interface\AddOns\SentinelGrudge\SentinelGrudge.toc
```

Enable Sentinel PvP as well. `/grudge` opens the list.

## What "attacked" means

Forever has no combat log, so Sentinel cannot attribute damage. In this addon, **attacked** means that player targeted you during a Sentinel-recorded fight (`targetedYou` on an enemy in `ForeverPvPIntelDB.worldHistory`). **Died** means that same fight also recorded your death (`deaths > 0`).

Attack counts, the past-attacker chat note, and Friendly auto-untag use that signal. If a client does expose a combat log, Grudge uses it as well. Forever does not.

## Commands

`/grudge help` prints this list. For `kos`, `friend`, and `clear`, omit the name to use your current target. A bare name is matched against Sentinel's records (most recently seen wins); `Name-Realm` picks a specific character.

- `/grudge` — open or close the list (sort by attacks, seen, recent, or name; filter by tag)
- `/grudge show` — same as `/grudge`
- `/grudge kos [name]` — tag KOS
- `/grudge friend [name]` — tag Friendly (`friendly` is accepted too)
- `/grudge clear [name]` — remove a tag
- `/grudge alert on|off|test|unlock|lock|reset` — on-screen KOS warning. `test` shows a sample. `unlock` lets you drag it, `lock` keeps the new position, and `reset` restores the default spot
- `/grudge sound on|off` — KOS warning sound
- `/grudge chat on|off` — KOS chat line
- `/grudge attacker on|off` — chat note when a past attacker is seen again
- `/grudge sentinelkos on|off` — treat Sentinel's watchlist (KoS) entries as KOS
- `/grudge tooltip on|off` — tooltip line
- `/grudge autountag on|off` — remove a Friendly tag if that player attacks you (default ON)
- `/grudge minimap on|off` — show or hide the minimap button
- `/grudge raidwarn on|off` — also show the KOS text in the raid-warning area
- `/grudge reset confirm` — delete Grudge tags and the guild cache. Sentinel's records stay as they are. Without `confirm`, the command only explains what it will delete

Leaving `on`/`off` off a toggle command flips that setting.

The minimap button is a skull icon. Left-click opens the list, right-click toggles the on-screen KOS warning, and dragging moves it around the minimap edge. The angle and hidden state are saved in `SentinelGrudgeDB.settings`.

## What it stores

From Sentinel (`ForeverPvPIntelDB`, read by Grudge):

- **Seen** — `players[guid].encounters`, plus first and last seen, zone, class, level, race, kills, and Sentinel's own KoS flag.
- **Attacked you** — how many Sentinel world-history fights had that enemy targeting you. **Died** — how many of those fights included your death.

Grudge's own saved variables (`SentinelGrudgeDB`): KOS and Friendly tags, a guild cache (filled in when a hostile or tagged player is seen), settings, and the warning position.

Auto-untag (v1.2.0) drops a Friendly tag when that player attacks. The signals are a new Sentinel fight where they targeted you, the combat log when the client has one, and a hostile Friendly-tagged unit who is in combat and targeting you while you are in combat. It removes the Friendly tag and does not add a KOS tag. Toggle it with `/grudge autountag`.

## Releasing

Tagged releases are built with the [BigWigs packager](https://github.com/BigWigsMods/packager) (`BigWigsMods/packager@v2`). The workflow is `.github/workflows/release.yml`. Push an annotated tag named `v*` (for example `v1.2.0`) and the workflow packages the addon, attaches the zip to a GitHub release, and uploads to CurseForge when that upload is configured.

The workflow supplies:

- `CF_API_KEY` from the repository secret `CF_API_KEY`
- `GITHUB_OAUTH` from the built-in `GITHUB_TOKEN`

The CurseForge project id is not known yet, so `SentinelGrudge.toc` has no `## X-Curse-Project-ID` line. With that line absent, or with `CF_API_KEY` unset, the packager skips the CurseForge upload and the workflow still succeeds. The GitHub release is published from `GITHUB_TOKEN`.

When the CurseForge project exists:

1. Create an API token at [authors.curseforge.com](https://authors.curseforge.com/#/settings/api-tokens) and save it as the repository secret `CF_API_KEY`.
2. Copy the numeric project id from the About Project box on the project page.
3. Add this line to `SentinelGrudge/SentinelGrudge.toc`:

```
## X-Curse-Project-ID: 123456
```

Replace `123456` with the real id. Then tag and push the next version. The packager uploads that tag to CurseForge and to the GitHub release.

`.pkgmeta` sets `package-as: SentinelGrudge` and moves `SentinelGrudge/SentinelGrudge` to `SentinelGrudge`, so the zip contains one addon folder. It leaves `README.md`, `test`, `LICENSE`, `.github`, and `.gitignore` out of the zip. It records the runtime dependency on ForeverPvPIntel (Sentinel PvP). That addon is installed separately and is not downloaded as a packager external. `required-dependencies` is sent to CurseForge as a project slug; if CurseForge rejects `ForeverPvPIntel` once uploads are enabled, replace that entry with the Sentinel PvP project slug.

## Tests

`test/harness.lua` is a mock-API check (Lua 5.1, for example lupa). It is kept out of the packaged addon.
