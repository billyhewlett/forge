# AIForge Cube — Art Preferences

All cards in `AIForge.dck` have explicit `|SET` codes. The ones below were
deliberately chosen for a preferred printing. Cards not listed here use
whatever set code was already in the file.

**Standard**: the user wants each card's *true original historical printing*, not
just "an old-looking" or same-artist reprint. Verify against the actual edition file
(`grep -n "Card Name" "forge-gui/res/editions/<Set Name>.txt"`) before trusting a doc
note or an artist credit — Sol Ring was documented as "Mark Tedin art" but pinned to
`CMD` (2011), whose actual art is by Mike Bierek; Tedin's art is the `3ED` (Revised)
printing. Don't assume a note is correct just because it sounds plausible.

**Diagnostic technique**: to verify a data-file push actually reached the live app
(as opposed to landing in an unread path or being masked by a stale cache), temporarily
remove one card's line from `AIForgeRankings.txt`, push, force-stop, and confirm that
exact card shows a 0/unrankable rating in-draft. A clean 0 proves the push path is real
and live; anything else means you're not editing the file the app actually reads. Revert
the rankings edit immediately after confirming — don't leave a card at 0 by accident.

## White
| Card | Set | Notes |
|---|---|---|
| Stoneforge Mystic | WWK | Original printing |
| Thalia, Guardian of Thraben | DKA | Original printing |
| Elite Spellbinder | STX | Original printing |
| Swords to Plowshares | 3ED | Anson Maddocks art (not Ice Age) |
| Balance | 4ED | Black border |
| Mother of Runes | ULG | Original Urza's Legacy art |

## Blue
| Card | Set | Notes |
|---|---|---|
| Brainstorm | ICE | Original Ice Age art |
| Flash | MIR | Original Mirage art |
| Mana Drain | LEG | Original Legends art |
| Mana Leak | STH | Original Stronghold art |
| Memory Lapse | HML | Original Homelands art |
| Ponder | LRW | Lorwyn art |
| Force of Will | ALL | Original Alliances art |
| Tinker | ULG | Original Urza's Legacy art |
| Echo of Eons | MH1 | Original Modern Horizons art |
| Urza, Lord High Artificer | MH1 | Original Modern Horizons art |

## Black
| Card | Set | Notes |
|---|---|---|
| Dark Confidant | RAV | Original Ravnica art |
| Dark Ritual | 4ED | Black border |
| Fatal Push | AER | Original Aether Revolt art |
| Vampiric Tutor | VIS | Original Visions art |
| Dismember | NPH | Original New Phyrexia art |
| Snuff Out | MMQ | Original Mercadian Masques art |
| Mind Twist | 4ED | Black border |
| Thoughtseize | LRW | Original Lorwyn (2007) art, Aleksi Briclot |
| Animate Dead | 4ED | Black border |
| Necromancy | VIS | Original Visions art |
| Demonic Tutor | 3ED | Revised art |
| Reanimate | TMP | Original Tempest art (Robert Bliss) - user wants the classic original, not the 2024 DSC reprint |
| Duress | USG | Original Urza's Saga art |
| Tendrils of Agony | SCG | Original Scourge art |

## Red
| Card | Set | Notes |
|---|---|---|
| Goblin Welder | ULG | Original Urza's Legacy art |
| Through the Breach | CHK | Original Champions of Kamigawa art |
| Chain Lightning | LEG | Original Legends art |
| Goblin Bombardment | TMP | Original Tempest art |
| Fury | MH2 | Original Modern Horizons 2 art |

## Green
| Card | Set | Notes |
|---|---|---|
| Birds of Paradise | 4ED | Black border |
| Hexdrinker | MH1 | Original Modern Horizons art |
| Outland Liberator | MID | Original Midnight Hunt art |
| Eternal Witness | 5DN | Original Fifth Dawn art |
| Questing Beast | ELD | Original Eldraine art |
| Woodfall Primus | SHM | Original Shadowmoor art |

## Multicolor
| Card | Set | Notes |
|---|---|---|
| Fractured Identity | C17 | ⚠️ No art found — may need different set |
| Fallen Shinobi | MH1 | Original Modern Horizons art |
| Fire Covenant | ICE | Original Ice Age art |
| Ignoble Hierarch | MH2 | Original Modern Horizons 2 art |

## Lands
| Card | Set | Notes |
|---|---|---|
| Wasteland | TMP | Original Tempest art (black border) |
| Flooded Strand | ONS | Original Onslaught art |
| Hallowed Fountain | DIS | Original Dissension art |
| Temple Garden | RAV | Original Ravnica art |
| Sacred Foundry | RAV | Original Ravnica art |
| Blood Crypt | DIS | Original Dissension art |
| Stomping Ground | GPT | Original Guildpact art |
| Steam Vents | GPT | Original Guildpact art |
| Watery Grave | RAV | Original Ravnica art |
| Overgrown Tomb | RAV | Original Ravnica art (was missing from this list, silently pinned to ECL) |
| Godless Shrine | GPT | Original Guildpact art (was missing from this list, silently pinned to EOE) |
| Breeding Pool | DIS | Original Dissension art (was missing from this list, silently pinned to EOE) |

## Artifacts
| Card | Set | Notes |
|---|---|---|
| Walking Ballista | AER | Original Aether Revolt art |
| Karn, Scion of Urza | DOM | Original Dominaria art |
| Chrome Mox | MRD | Original Mirrodin art |
| Mishra's Bauble | CSP | Original Coldsnap art |
| Zuran Orb | ICE | Original Ice Age art |
| Chromatic Star | TSP | Original Time Spiral art |
| Retrofitter Foundry | C18 | Original Commander 2018 art |
| Sol Ring | 3ED | Mark Tedin art, original Revised Edition printing (was mispinned to CMD, whose actual art is by Mike Bierek, not Tedin) |
| Lightning Greaves | MRD | Original Mirrodin art |
| Umezawa's Jitte | BOK | Original Betrayers of Kamigawa art |
| Nettlecyst | MH2 | Original Modern Horizons 2 art |
| Mana Crypt | 2XM | Double Masters art |
| Skullclamp | DST | Original Darksteel art |
| Pentad Prism | 5DN | Original Fifth Dawn art |
| Soul-Guide Lantern | THB | Original Theros Beyond Death art |
| Lotus Petal | TMP | Original Tempest art (April Lee) |

## Black
| Card | Set | Notes |
|---|---|---|
| Entomb | ODY | Original Odyssey art (Ron Spears) |

## Red
| Card | Set | Notes |
|---|---|---|
| Lightning Bolt | 4ED | Black border (Christopher Rush) |

## To investigate / fix
- **Fractured Identity** — tried C17 and WHO, neither has art. May not be downloaded.

## Known root cause of recurring "art broke" reports (2026-08-15)
Cube/draft/rankings files (`AIForge.dck`, `AIForge.draft`, `AIForgeRankings.txt`) are read
by Forge Android **only** from the OBB bundle path
(`/sdcard/Android/obb/forge.app/Forge/res/...`), which is baked in at APK install time.
The documented push pipeline in `AIFORGE_CONTEXT.md` (Step 6) pushes to
`/sdcard/Android/data/forge.app/files/...` instead — a path Forge never reads for these
files (`ForgeConstants.DECK_CUBE_DIR`/`DRAFT_DIR` both resolve under the OBB `res/` dir on
Android). Any `.dck`/rankings fix pushed via the old pipeline silently never took effect
until the next full APK reinstall. Push data-file updates to the OBB `res/` path instead,
e.g. `adb push forge-gui/res/cube/AIForge.dck /sdcard/Android/obb/forge.app/Forge/res/cube/AIForge.dck`.
