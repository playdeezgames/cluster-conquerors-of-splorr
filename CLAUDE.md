# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**Cluster Conquerors of SPLORR!!**, a new game by TheGrumpyGameDev, started November 10, 2026: an homage to the original DOS Master of Orion (SimTex and MicroProse, 1993), a turn-based space 4X, mashed up with the tropes of SPLORR!! games the way Blustery Bulwark of SPLORR!! was made from Castle of the Winds.

It is **an homage, not a remake** of Master of Orion. Do not reuse its races, race names, leader names, story, text, icons or art (no Psilons, Klackons, Darloks, Mrrshan, Sakkra, Silicoids, Alkari, Bulrathi, Meklars; no Orion or Guardian by those names; the stand-ins are the Clubhouse and its space moth). Genre mechanics (colony sliders, ship design, range, tech fields, a galactic council vote) are fair game.

`DESIGN.md` is the specification. It records the user's decisions (dated, in their words; the twelve proposals and the details were all decided November 10, 2026), the two trope inventories and what is still open; only the user moves an item to Decided. **Nothing is built yet: stay in design until the user says to build.**

The vault at `/home/yermom/git/bok-of-splorr/splorr/` is the shared body of knowledge for all SPLORR!! games and holds the standing rules. Read its `Home.md` first. This game's note is `Games/Cluster Conquerors of SPLORR!!.md`. When a decision or a fact about the game changes, update that note and its `Home.md` row as well. `Gotchas.md` in the vault has the WebGL, wasm RNG and Odin lessons; read it before writing code. The stack (decided November 10, 2026) is the vault default: Odin to `js_wasm32`, a canvas software framebuffer, web only, as in `Tech/Odin wasm recipe.md` and Blustery Bulwark's repo (`/home/yermom/git/blustery-bulwark-of-splorr`).

## Standing rules (full text in the vault's `Home.md`)

- **"Push" means `git push`; "ship" means itch.io.** Do neither unless the user says that word. One ship a day through Coxswain (`ship_today` before, `ship_complete` after); scheduling is not permission.
- **GitHub Pages first.** The repo is public (`playdeezgames/cluster-conquerors-of-splorr`); Pages comes once there is something playable, served from `main` `/docs` (`Tech/GitHub Pages.md`), each push on the user's go-ahead.
- **Release standard** from the start (`Tech/Release standard.md`): `ITCH_DESCRIPTION.md`, `assets/cover.png` (630 by 500), `assets/screenshots/`, `devlog/YYYYMMDD/`, `tools/ship.sh` and a one-line `shippit.sh` that pushes only with `--push`. The page footer carries back links, the AI disclosure and a "Send feedback" link to the shared LootLocker form (`Tech/LootLocker.md`).
- **Public repo: no 1-Bit Kingdom art**, ever. Prefer CC0 sets (Urizen, Bountiful Bits, Bit Bonanza) and keep every licence record and credit.
- If the ROM font 8x8 turns up, ask the user before replacing it (DINOBYTE first, then Public Pixel).
- In player-facing text and itch copy the game is a **"Metaphor"**, never a "Game", and the voice says **"yer"**, never "your" or "you're".
- Do not describe or "fix" deliberate design (brutality, odd rules) as a problem once the user has decided it.
- Anything an AI agent posts on itch.io says it was posted by an AI agent.
