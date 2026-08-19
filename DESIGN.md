# Tribunal — Design Language

**Addon:** Tribunal — *The Mythic+ Wipe Court*
A party votes on who caused the wipe. Verdicts accrue to a permanent leaderboard.

## Concept

An obsidian courtroom. Ceremonial but restrained — this is a *verdict*, not a
carnival. The tone is dry, ritual, faintly ominous, and funny precisely because
it takes itself seriously. Think a high court's brass and black marble, rendered
with the restraint of a modern product UI.

Explicitly NOT: chunky Blizzard gold scrollwork, parchment, wood grain, gemstones,
drop-shadowed bevels, or anything that reads "2008 WoW addon".

## Palette

| Token        | Hex       | Use |
|--------------|-----------|-----|
| `void`       | `#0B0D12` | Outermost backdrop, knockouts |
| `panel`      | `#12151D` | Frame body |
| `raised`     | `#1A1E28` | Rows, cards, inputs |
| `raisedHi`   | `#232833` | Hover and selected rows |
| `hairline`   | `#2A303D` | 1px separators, frame edge |
| `gold`       | `#E8B23A` | State: selected, first, active, counting down |
| `goldLight`  | `#FFD98A` | Highlight edge, glow core |
| `crimson`    | `#C4383A` | Blame, the accused, danger |
| `jade`       | `#3FBF8F` | Cleared, safe, confirm |
| `text`       | `#E8E4DA` | Primary type (warm off-white) |
| `textMuted`  | `#8A8E9C` | Secondary type (cool, so it separates) |
| `textDim`    | `#4A5162` | Tertiary, metadata |

**Gold marks state — never structure, never decoration.**

It is allowed on: the option you selected, the entry ranked first, the control
that is currently active, and the countdown. It is not allowed on a section
heading, a container, a separator, or a value that every row in a list has. If
a list paints something gold on all sixty rows, gold has stopped meaning
anything.

Three things are **chrome**, not marks: the header emblem, the hairline rule
beneath it, and the diamond divider on the verdict. They are the addon's
signature and recur by design. Count them once, not once per screen.

On the verdict screen gold is **light, not a mark** — the bloom, the rays, and
the glyph struck into the seal. Every actual mark there is crimson: the name,
the seal's ring, the leading tally bar.

The panel/row separation is nine levels of value. Nothing may erode it — in
particular the panel grain must **blend**, never add.

## Form

- **8px rhythm.** Every panel layout constant is a multiple of 8 — widths
  384/392/424, padding 16, row heights 32/40, gaps 8, section breaks 24,
  footers 48. The only exceptions are optically-centred elements and the 26px
  minimap button, which belongs to the minimap's geometry, not the panel grid.
- **Anything anchored to the bottom of a panel needs a `maxWidth`.** Twice now
  a label with no bound has run under the control beside it.
- 1px hairlines only. No bevels, no inner highlights, no drop shadows, no
  double edges.
- Corners are square. Discs are circles cut with a mask, never rounded rects.
- Generous negative space; a panel should feel underfilled rather than packed.
- Type: uppercase with wide tracking for labels, sentence case for content.
  Two faces only — `FRIZQT__` for everything, `ARIALN` for numerals. No display
  face: a costume font undoes the restraint the rest of the system buys.
- Depth comes from *value* — `panel` against `raised` — and from nothing else.

## Surfaces

There are two, and which one a window gets depends on how it arrived.

**Solid** is the obsidian slab: the docket and the settings. You opened those,
so the game can wait behind them.

**Veil** is for the two windows nobody asked for — the ballot and the verdict.
They open on their own while people are still running back, and a slab dropped
over a fifth of the screen at that moment is rude. So these windows have **no
background at all**. Not a faint one — none. What draws is the type, the
portraits, the hairlines, the corner ticks and the marks, held over whatever
the game is showing. There is no panel fill, no grain, no row backing and no
plate under any block of text.

That means depth stops coming from a surface, because there isn't one. It comes
instead from the type's own counter-edge, which is why the shade does not scale
with the setting: at zero backing it is the only thing standing between a 10px
tracked cap and a snowfield.

`TribunalDB.settings.opacity` scales every backing alpha together and is **0 by
default**. Anyone who plays somewhere bright enough to want a surface can dial
one in; at 1.0 the windows carry a full panel fill, grain, row backing and
plates, and the relationship between them is the same as it ever was — a row is
content and stays denser than the container it sits in. `edge` and `shade` are
structure rather than background and never scale away.

**The one shadow.** Veiled type carries a 1px hard black shadow at 0.85, no
blur. This is not the drop shadow banned below: that one is a fake light source
used to lift a panel off the screen, and it is visible on obsidian. This one is
a single-pixel dark counter-edge that exists solely so 10px tracked caps
survive a snowfield, and it is off entirely on the solid windows, where value
still does all the work.

## Motion

**The strike is the signature.** Nothing gold ever fades in — it is struck,
opening outward from its own centre in a fast decelerating sweep. The header
rule strikes when a window opens. The accent bar strikes when you select a row.
The tab underline strikes when you switch view. It is one gesture, `outQuint`
over ~220ms, and it is the only thing every screen in the addon does the same
way. The gavel is the metaphor; `Theme:Strike` is the whole of it.

- Every state change eases. `outQuint` for entrances, `outCubic` for the rest.
- Ballot rows stagger in at 45ms intervals.
- Result bars sweep left→right with a leading edge that fades.
- **A glow has exactly one owner.** Two tweens writing the same alpha will
  fight, and the loser's contribution is invisible until the winner ends.
- **Never cut a decorative alpha to zero.** Anything the viewer watched arrive
  must settle to a resting value; deleting it reads as a bug.
- Nothing bounces. Nothing spins. Restraint reads as expensive.

## Art

Everything is flat, graphic, and near-monochrome. Textures are authored as
**white with alpha only** — the code owns colour via `SetVertexColor`, so a
pre-tinted asset would be multiplied twice and land off-palette.

| Asset | Size | Use |
|-------|------|-----|
| `Emblem` | 256 | The mark: scales, geometric, 2px linework |
| `MinimapIcon` | 64 | The mark redrawn to hold at 17px |
| `PanelTile` | 256 | Seamless panel grain, ~3 levels of luma |
| `Bloom` | 256 | Soft radial glow, gaussian falloff |
| `Rays` | 256 | 15 tapered spokes at three lengths, hollow core |
| `Divider` | 256×32 | Hairline rule with a centre diamond |

## Portraits

The ballot shows each defendant's portrait, because voting on a person is
easier when you can see which person. Blizzard's portrait art is busy and
colourful — the opposite of everything else here — so it is admitted on this
system's terms: cut with the same circular mask as the seal and the minimap
button, ringed with a 1px stroke in the class colour, at 28px.

That ring does double duty. It carries class identity, so the old 6px chip is
redundant; and when you select a row it turns gold, which is how the ballot
marks your choice without adding a new element.

Portraits only exist for units the client can currently see, and a ballot is
most likely to be open while people are running back from a wipe. So it
degrades: portrait, then the class icon, then a flat class-coloured disc. A row
that fell back is retried until it resolves. The quieter chip list is still
available in settings.

The verdict seal is **drawn in code**, not textured: it has to change colour
with the outcome, and a flat 1px ring is what this language actually asks for.
Its face is drawn slightly transparent so the bloom behind it reads through —
opaque, a lit seal eclipses its own light.

## Failure states

A hung jury and a deadlock are outcomes, not errors. They get a smaller
ceremony — a shorter stage, a smaller seal in `textDim` — rather than the
conviction layout with the colour drained out of it.

## Audio

Low, ceremonial, sparse. Struck metal and deep wood. No fanfare, no cheering.
The sound of a heavy door closing in a stone room.
