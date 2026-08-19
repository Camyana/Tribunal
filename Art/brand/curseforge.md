# CurseForge store copy

Paste-ready. Keep this in sync with the README when either changes.

---

## Summary  (the one-line field, 158 characters)

Someone caused that wipe. Tribunal lets your Mythic+ party hold a secret ballot on who, reveals the verdict, and keeps a permanent record of the convictions.

---

## Description

![Tribunal](https://raw.githubusercontent.com/Camyana/Tribunal/main/Art/brand/header.png)

**Somebody caused that wipe.** Tribunal is the court that decides who.

Out of combat, anyone in the group calls the court to order. Everyone running
the addon gets a ballot — the party list, a countdown, and a live count of how
many votes are in. Not *who* voted for whom. That comes later.

When the clock runs out the ballots are counted and the verdict is read, and
the convicted player's name goes on the docket. Permanently.

---

### It takes itself completely seriously

That is the joke. There is no confetti, no sad trombone, no comedy font. There
is a gavel, a countdown, a wax seal, and a name. The humour is in how gravely
a group of five adults can be made to deliberate over who stood in the swirly.

---

### What you get

**A secret ballot.** You see that four people have voted, not what they voted.
Change your mind as often as you like until the clock runs out — the last vote
is the one that counts. The reveal is the reveal.

**Portraits on the ballot**, so you are voting on a face rather than a name.
Ringed in the class colour, and the ring turns gold on the one you picked.
Anyone out of range falls back to their class icon and upgrades the moment they
come back into view — which matters, because half the party is usually running
back when the court convenes.

**A verdict worth waiting for.** The seal lands, the light comes up, the name
arrives, and the tally fills in behind it. A hung jury and a deadlock get their
own shorter ceremony rather than the conviction screen with the colour drained
out of it.

**A permanent docket.** Convictions, trials stood, conviction rate, votes cast
and votes received, tracked per character across every group you play with.
Sortable, with a running history of recent verdicts.

**Sound design for the court.** A gavel to open, a wooden tap when you cast, a
quiet tick over the last five seconds, a bronze bell for the verdict, and an
optional low drone underneath the vote. All of it toggleable, on the channel of
your choosing.

**A minimap button with a drawer.** Convene, docket, settings. Drag it around
the ring. Right-click goes straight to the leaderboard.

**An optional prompt after a wipe.** When the whole party goes down, a small
toast asks whether to convene. It never opens a ballot on its own, and you can
turn it off entirely.

---

### Commands

| Command | Does |
|---|---|
| `/trib` | Open the leaderboard |
| `/trib vote` | Call the court to order |
| `/trib config` | Settings |
| `/trib who` | Who in the group has the addon |
| `/trib minimap` | Toggle the minimap button |
| `/trib reset` | Expunge the docket |

---

### Worth knowing

- **Everyone who wants to vote needs the addon.** `/trib who` tells you who has
  it. Players without it still appear on the ballot and can still be convicted —
  they just do not get to vote, and never know.
- **Nothing leaves your machine.** The docket is stored in your own saved
  variables. Votes travel over the addon channel to your party and nowhere else.
- **A vote cannot be forged.** The sender is taken from the game's own message
  event rather than the payload, so nobody can cast a ballot in your name.
- **No library dependencies.** Nothing to install alongside it.

---

### Settings

Ballot length, cooldown between trials, secret ballot on or off, whether you
can convict yourself, the post-wipe prompt, verdict announcements in party
chat, portraits, every sound and its output channel, window scale, and the
minimap button.

---

*Built for retail. Report anything broken on
[GitHub](https://github.com/Camyana/Tribunal/issues).*
