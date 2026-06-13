# DropOne

**DropOne** is a fast-paced, online multiplayer card game built with **Godot 4**. Match colors and numbers, stack draw penalties, play wild cards, and be the first to empty your hand.

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.1.7-blue" alt="Version" />
  <img src="https://img.shields.io/badge/engine-Godot%204.6-478CBF?logo=godotengine&logoColor=white" alt="Godot 4.6" />
  <img src="https://img.shields.io/badge/players-2--8-green" alt="2-8 players" />
  <img src="https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white" alt="Windows" />
</p>

---

## Features

| | |
|---|---|
| **Online multiplayer** | Steam lobbies with up to 8 players, or local LAN-style testing without Steam |
| **Singleplayer** | Practice against AI bots with adjustable difficulty and personality |
| **Custom decks** | Host picks the deck in the lobby — Classic, Default, DefaultPlus, and more |
| **Special cards** | Skip, Reverse, Draw +2/+4, Wild, Target Draw, Swap Hands, Place All, Color Roulette, and more |
| **Smart UI** | Dynamic hand layout with card overlap, hover descriptions, and smooth fly animations |
| **1v1 rules** | Reverse acts as Skip; Wild Draw Reverse makes you draw in duels |

---

## Download

Pre-built Windows builds are available on the [**Releases**](https://github.com/11samy02/DropOne/releases) page.

1. Download `DropOne-Windows-v0.1.7.zip`
2. Extract the folder
3. Launch **`DropOne.exe`**
4. Keep `steam_appid.txt` and the Steam DLLs next to the executable

> **Steam required.** The game uses Steamworks for lobbies and networking (test App ID `480` for development builds). Host and clients must run the **same version**.

---

## How to Play

1. **Create your profile** on first launch (name + avatar).
2. **Create or join a lobby** from the hub — or start **Singleplayer** against bots.
3. When everyone is ready, the host starts the match.
4. On your turn, play a card that matches the **color** or **number/type** of the top discard card, or draw from the deck.
5. First player to play their last card wins.

**Hover any card in your hand** to see an English description of its color, value, and effect.

---

## Special Cards (overview)

| Card | Effect |
|------|--------|
| **Skip** | Next player loses their turn |
| **Reverse** | Reverses direction (in 1v1: skips opponent) |
| **Draw +2 / +4** | Next player draws; stackable with matching draw cards |
| **Wild** | Choose any color |
| **Wild +4** | Choose a color; next player draws 4 |
| **Target Draw** | Pick an opponent to draw |
| **Multi Target Draw** | All other players draw |
| **Swap Hands** | Swap hands with a chosen player, then pick a color |
| **Place All** | Play all cards of one color, then pick a new color |
| **Color Roulette** | Next player must match your chosen color or keep drawing |

---

## Development

### Requirements

- [Godot 4.6+](https://godotengine.org/download)
- Steam client (for multiplayer testing)
- Windows export templates (for building releases)

### Run from source

```bash
git clone https://github.com/11samy02/DropOne.git
cd DropOne
# Open project.godot in Godot and press F5
```

### Local multiplayer without Steam

In the lobby hub scene, set **`use_steam = false`**, then run two instances — one as host, one as client on `127.0.0.1`.

### Export (Windows)

```bash
godot --headless --export-release "Windows Desktop" path/to/DropOne.exe
```

Include alongside the executable:

- `DropOne.pck` (if not embedded)
- `steam_api64.dll`
- `libgodotsteam.windows.template_release.x86_64.dll`
- `steam_appid.txt`

---

## Project Structure

```
DropOne/
├── Scenes/          # UI, game table, card views
├── Scripts/         # Game logic, networking, AI, Steam
├── Resources/Decks/ # Deck definitions
├── Assets/          # Card art, UI textures, avatars
└── addons/godotsteam/
```

---

## Tech Stack

- **Engine:** Godot 4.6 (GDScript)
- **Networking:** Authoritative host/server model with RPC sync
- **Steam:** GodotSteam (lobbies, P2P relay)
- **AI:** Built-in bot controller with difficulty & personality presets

---

## Versioning

Lobby matchmaking filters by game version — all players in a match must share the same build tag (e.g. `v0.1.7`).

---

## License

Third-party components (e.g. GodotSteam) carry their own licenses. See `addons/godotsteam/license.md`.
