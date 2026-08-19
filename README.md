# Tribunal

**The Mythic+ Wipe Court.**

Somebody caused that wipe. Tribunal lets your party hold a vote about who, and
keeps a permanent record of the verdicts.

---

## What it does

Out of combat, anyone in the group can convene the court. Everybody running the
addon gets a ballot: the party list, a countdown, and a running count of how many
votes are in — but not who voted for whom. When the clock runs out the ballots are
counted and the verdict is read with an animated reveal. The convicted player's
tally goes up, permanently, on the leaderboard.

- **Secret ballot by default.** You see *that* four people have voted, not what
  they voted. The reveal is the reveal.
- **Portraits on the ballot**, ringed in the class colour, falling back to the
  class icon for anyone out of range and upgrading as they come back into view.
  Switchable back to a plain chip list in settings.
- **Change your mind** any time before the clock runs out. Last vote counts.
- **Deadlocks and abstentions are real outcomes.** A tie convicts nobody. If
  nobody votes at all the trial isn't recorded.
- **Wipe detection** offers a prompt when the whole party goes down. It never
  opens a ballot on its own.
- **The docket** tracks convictions, trials stood, conviction rate, votes cast,
  and votes received, per character, across every group you play with.

## Using it

Click the minimap button to open the drawer — convene, docket, settings.
Right-click it to jump straight to the leaderboard. Drag it around the ring.

```
/trib            open the leaderboard
/trib vote       call the court to order
/trib config     settings
/trib who        who in the group has the addon
/trib minimap    toggle the minimap button
/trib reset      expunge the docket
```

Everyone who wants to vote needs the addon. `/trib who` tells you who has it.
Players without it simply don't receive a ballot — they can still be convicted.

## Requirements

Retail World of Warcraft, interface 12.1.0. No library dependencies.

---

## How it is built

```
Core.lua              namespace, saved variables, events, slash commands
Modules/Anim.lua      tween engine; one OnUpdate drives every animation
Modules/Theme.lua     the entire widget vocabulary and palette
Modules/Comm.lua      addon-channel transport and peer discovery
Modules/Session.lua   the trial state machine, tally, and record keeping
Modules/Ballot.lua    the voting window and the post-wipe prompt
Modules/Verdict.lua   the animated reveal
Modules/Board.lua     standings and recent verdicts
Modules/Minimap.lua   minimap button and drawer
Modules/Config.lua    settings
```

Everything visual resolves through `Theme.lua`; see `DESIGN.md` for the design
language it implements. `Verdict.lua` keeps its choreography in a single `CUE`
table, so the feel of the reveal can be retimed without touching the animation
code.

### Protocol

Messages go over the `TRIBUNAL` addon channel, pipe-delimited, opcode first.
The sender is always taken from the `CHAT_MSG_ADDON` event rather than the
payload, so a vote cannot be attributed to somebody else.

| Op | Payload | Meaning |
|----|---------|---------|
| `HI` / `YO` | protocol, version | presence handshake |
| `V` | session, duration, label | open a ballot |
| `C` | session, target | cast a vote |
| `R` | session, winner, count, total | the initiator's authoritative result |
| `X` | session, reason | withdraw the trial |

Every client tallies independently and deterministically (count descending,
then name ascending), so they agree without needing to talk. The initiator's
`R` message is still authoritative, and the reveal's "counting the ballots"
beat exists partly to give it time to arrive.

Messages are only accepted from players currently in your group.

### Testing

The addon can be loaded and driven entirely outside the game:

```bash
python Tools/luacheck.py
```

```bash
python Tools/runsim.py
```

`luacheck.py` compiles every file under a real Lua 5.1 runtime. `runsim.py`
loads the addon against a World of Warcraft API mock (`Tools/wowmock.lua`) and
drives full scenarios through it — a majority verdict, a deadlock, a hung jury,
a trial called by somebody else, a spoofed result, combat interrupting the
court, leaving the group mid-trial, and wipe detection — asserting on the
resulting saved variables. Both require `pip install lupa`.

### Media

`Media/Textures/*.tga` are 32-bit uncompressed TGAs at power-of-two sizes,
authored as **white with alpha only** — the code owns colour through
`SetVertexColor`, so a pre-tinted asset would be multiplied twice and land off
the palette. `Tools/png2tga.py` converts source PNGs; `Art/source/rework.py`
regenerates the procedural ones (grain, bloom, rays, divider, corner).

`Media/Sounds/*.ogg` are Ogg Vorbis, 44.1kHz, and are regenerated in full by
`Tools/mksounds.py` — every cue is procedural numpy synthesis, so the sound
design is editable rather than a set of opaque files. `Chamber.ogg` is built to
be exactly periodic over its 24 seconds (partials and LFOs snapped to the 1/24Hz
grid, noise beds built by inverse FFT), so it loops with no crossfade.

Every texture load goes through `Theme:Art`, and every caller pairs it with a
drawn fallback — a masked disc for the seal, a plain diamond for the minimap
mark, and so on. Setting `Theme.useArt = false` runs the whole UI on those
fallbacks, which is useful for seeing how much of the design is carried by
geometry rather than by art. It is not a missing-file guard: WoW reports
nothing when a texture fails to load.

## Licence

MIT.
