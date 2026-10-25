# BuffTrack

An [Ashita v4](https://www.ashitaxi.com/) addon for Final Fantasy XI that helps mages manage their duties: who needs which buff, who needs an esuna, and what enemy buffs are worth dispelling. Alerts show as on-screen text, with optional audio cues.

Built for **Ashita v4.30** on the **PhoenixXI** server. It should work on other LandSandBoat (LSB) servers.

> **Status:** posted publicly for peer review only. Not intended for distribution or support. The code was written through Claude prompts.

## Features

BuffTrack has three independent panels. Each can be positioned, scaled, and locked on its own, and they snap to each other.

| Panel | Purpose |
|-------|---------|
| **Grid** | Buff assignments: pick which buffs each party/alliance member should have and see at a glance who is missing one. Group by buff (columns) or by player (one panel per player). |
| **Cures** | Curable debuffs on party members (for Esuna/Erase-type duties). Reads status icons directly from memory. |
| **Watch** | Dispellable buffs that enemies cast on themselves, based on a watch list you maintain. |

Other highlights:

- **Per-player, per-spell display options.** Scale, color, sound, and flash resolve in this order: per-(player, spell) override, then per-spell override, then tracker default.
- **Audio cues** per tracker (Grid / Cures / Watch), with a preview button next to every sound picker.
- **Party tab** for player-centric setup: pick a player, see and edit their assigned buffs and Cures overrides.
- **Profiles** to save, load, and undo whole setups.
- **Job icons** (3 styles) and an optional dark-and-gold config theme.
- Passive only: the addon does not send outgoing packets.

## Installation

1. Download `BuffTrack-v1.0.zip` from the [Releases](../../releases) page.
2. Extract it so the folder lands at `<Ashita>\addons\BuffTrack`.
3. In game, run `/addon load bufftrack`.
4. To load it at startup, add `/addon load bufftrack` to your Ashita default script.

## Usage

Run `/bufftrack` to open the configuration window (tabs: Behavior, Buffs, Party, Cures, Watch).

| Command | Description |
|---------|-------------|
| `/bufftrack` | Open the configuration menu |
| `/bufftrack [buff] [player]` | Assign a buff to a party/alliance member |
| `/bufftrack cbuff [buff]` | Remove a buff column (all players) |
| `/bufftrack cplayer [player]` | Remove a player row (all buffs) |
| `/bufftrack watch [spell\|ability\|mobskill] [name]` | Add an enemy-buff watch entry |
| `/bufftrack unwatch [name]` | Remove a watch entry |
| `/bufftrack profile list` | List saved profiles |
| `/bufftrack profile save [name] [-p]` | Save the current setup (`-p` also saves panel positions) |
| `/bufftrack profile load [name]` | Load a saved profile |
| `/bufftrack profile delete [name]` | Delete a saved profile |
| `/bufftrack profile undo` | Restore the setup from before the last profile load |
| `/bufftrack reposition` | Unlock all panels so they can be dragged |
| `/bufftrack lock` | Lock panels and save their positions |
| `/bufftrack watchdebug` | Toggle printing every enemy action seen (for diagnosing watch entries that won't trigger) |
| `/bufftrack debugspell [name]` | Print a spell's raw `LevelRequired` field (diagnostic) |

**Tip:** Alt-click a live row to set per-player or per-spell overrides, or use the Party tab pickers to set them up ahead of time.

## Known limitations

- Erase's removal message for Watch alerts is not yet confirmed. Dispel has been verified live.
- Grid excludes Ability-type buffs.
- Watch is action-packet based, so enemy abilities with IDs below 256 are not handled.
- Party-tab job icons rely on an Ashita API call not yet verified on every build.

## Credits

Third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
