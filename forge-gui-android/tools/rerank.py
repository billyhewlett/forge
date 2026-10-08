import csv
import sys


# Cube cards listed under a flavor/alternate name (needed in the .dck so Forge
# selects the right printing/art) that must be translated to their true Oracle
# name here. Forge's card.getName() always returns the true name at runtime,
# never the flavor name, so a rankings entry left under the flavor name will
# silently fail lookup and the card will show a 0/unpickable rating in-game.
# This has come up before (e.g. LTC's "White Tower of Ecthelion" flavor-names
# the real card "Karakas") and will happen again with future cube additions —
# add new entries here as they're discovered, key = name as it appears in the
# CubeCobra/.dck export, value = the card's real Name: from its Forge script.
FLAVOR_NAMES: dict[str, str] = {
    "White Tower of Ecthelion": "Karakas",
}


def parse_cubecobra(filepath: str) -> list[tuple[int, str, str]]:
    """
    Parse CubeCobra file into list of (rank, name, raw_line).
    Format: #X|Card Name|C|CUSTOM, or a CubeCobra .dck export directly
    (its card order is the ELO order, worst first).

    Names are translated through FLAVOR_NAMES so every downstream step (ELO
    pinning, 17lands matching, and the final written rankings file) uses the
    card's true Oracle name, which is what Forge looks up at runtime.
    """
    entries = []
    with open(filepath, encoding="utf-8") as f:
        lines = [l.strip() for l in f]
    if filepath.lower().endswith(".dck"):
        # CubeCobra .dck export: card lines ("1 Name|SET") are ELO-ordered
        # worst -> best, so reverse them into "#N|Name|C|CUSTOM" lines.
        cards = [l.split(" ", 1)[1].split("|")[0] for l in lines if l[:1].isdigit()]
        lines = [f"#{i}|{name}|C|CUSTOM" for i, name in enumerate(reversed(cards), 1)]
    for line in lines:
        if not line:
            continue
        parts = line.split("|")
        rank = int(parts[0][1:])  # strip leading '#'
        name = parts[1]
        if name in FLAVOR_NAMES:
            real_name = FLAVOR_NAMES[name]
            parts[1] = real_name
            line = "|".join(parts)
            name = real_name
        entries.append((rank, name, line))
    return entries


def parse_17lands_values(filepath: str) -> tuple[str, dict[str, float]]:
    """
    Parse 17lands CSV. Returns card names best-to-worst.

    Two supported export formats, auto-detected from the header. ATA/ALSA is
    preferred whenever present, even if the export also includes GIH WR
    columns — the user wants actual human drafting behavior ("drafted"),
    not a computed in-game performance score ("scored").

      1. Pick-order export (columns: Name, ..., ATA, ALSA): reflects human
         perceived value at draft time, not measured performance.
           - ATA (Average Taken At) — direct pick number; most cards lack this.
           - ALSA (Average Last Seen At) — avg pack position when last seen;
             covers ~4x more cards. Lower = disappears from packs faster.
         Sort ascending — earlier pick = better rank.

      2. Win-rate export (columns: Name, ..., "GIH WR"): Games-in-Hand Win
         Rate is a direct performance metric ("how often do you win when you
         draw this card"). Only used as a fallback when ATA/ALSA aren't
         present at all. Sort descending — higher win rate = better rank.
         Percent strings like "63.5%" are parsed as floats.

    Cards with no data for the active metric are omitted and fall back to
    ELO rank (e.g. Power 9 often lack ATA/ALSA since they're always P1P1).

    Handles quoted names with commas via csv module.
    File may have a BOM, so we use utf-8-sig.
    """
    entries = []  # (sort_value, name)
    with open(filepath, encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)

        if "ATA" in header and "ALSA" in header:
            ata_idx  = header.index("ATA")
            alsa_idx = header.index("ALSA")
            for row in reader:
                ata  = row[ata_idx]  if len(row) > ata_idx  and row[ata_idx]  else None
                alsa = row[alsa_idx] if len(row) > alsa_idx and row[alsa_idx] else None
                val = ata or alsa  # prefer ATA; fall back to ALSA
                if val:
                    try:
                        entries.append((float(val), row[0]))
                    except ValueError:
                        pass
        elif "GIH WR" in header:
            wr_idx = header.index("GIH WR")
            for row in reader:
                val = row[wr_idx] if len(row) > wr_idx and row[wr_idx] else None
                if val:
                    try:
                        entries.append((-float(val.rstrip("%")), row[0]))
                    except ValueError:
                        pass
    metric = "ATA" if "ATA" in header and "ALSA" in header else "GIH WR"
    return metric, {name: val for val, name in entries}


def parse_17lands(filepath: str) -> list[str]:
    """Single-file ordering, best-to-worst (see parse_17lands_values)."""
    _, values = parse_17lands_values(filepath)
    return sorted(values, key=lambda n: (values[n], n))  # ascending = better (WR negated); ties by name


def merge_17lands(filepaths: list[str]) -> tuple[list[str], dict[str, str]]:
    """
    Multiple 17lands exports in priority order (newest/most important first).
    Each card takes its value from the FIRST file that has data for it, then
    all cards are sorted together by that value. Values are comparable across
    files because they're the same metric (ATA/ALSA = pick position), so a card
    only found in an older export interleaves correctly instead of being dumped
    below everything. Mixing metrics (ATA vs GIH WR) is refused: different scales.
    Returns (names best-to-worst, {name: source file}).
    """
    values: dict[str, float] = {}
    source: dict[str, str] = {}
    metrics = set()
    for fp in filepaths:
        metric, vals = parse_17lands_values(fp)
        metrics.add(metric)
        for name, val in vals.items():
            if name not in values:
                values[name] = val
                source[name] = fp
    if len(metrics) > 1:
        sys.exit(f"Refusing to mix 17lands metrics {sorted(metrics)} — use exports of one kind.")
    return sorted(values, key=lambda n: (values[n], n)), source


# Functional reprints or renamed cards that should inherit another card's 17lands rank.
# Key: name as it appears in the CubeCobra file.
# Value: name as it appears in the 17lands file.
NAME_ALIASES: dict[str, str] = {
}

# Cards to force-pin at their ELO position regardless of 17lands data.
# Normally not needed — cards with no ATA are auto-excluded — but kept as an
# explicit escape hatch for cards whose ATA data exists but is misleading.
PINNED_CARDS: set[str] = {
}


def build_reranked_list(
    cobra_entries: list[tuple[int, str, str]],
    lands_order: list[str],
) -> list[str]:
    """
    Algorithm:

    1. COLLAPSE: Walk the CubeCobra list and build a list of unique-card
       "slots".  Each slot records: name, count (1 or 2), and the raw_line
       template.  Consecutive duplicates in the input become a single slot
       with count=2.

    2. PIN: Mark slots whose card is NOT in 17lands (no ATA data) or is in
       PINNED_CARDS.  These stay at their current ELO-derived index.
       Cards in NAME_ALIASES use their alias's ATA rank.

    3. SORT & FILL: Sort the moveable slots by 17lands ATA rank.  Walk the
       collapsed list; whenever we hit a non-pinned slot, pop the next card
       from the sorted moveable list.

    4. EXPAND: Each slot becomes 1 or 2 output lines (based on count).

    5. RENUMBER: Assign ranks 1..N sequentially.
    """
    lands_set = set(lands_order)
    lands_rank = {name: i for i, name in enumerate(lands_order)}

    # --- Step 1: Collapse into unique-card slots ---
    # Each slot: (name, count, raw_line_template)
    collapsed = []
    i = 0
    while i < len(cobra_entries):
        rank, name, raw_line = cobra_entries[i]
        count = 1
        # Check if next entry is the same card (consecutive duplicate)
        if i + 1 < len(cobra_entries) and cobra_entries[i + 1][1] == name:
            count = 2
            i += 2
        else:
            i += 1
        collapsed.append((name, count, raw_line))

    def effective_name(name: str) -> str:
        """Return the 17lands lookup name for a card (alias if one exists)."""
        return NAME_ALIASES.get(name, name)

    def in_lands(name: str) -> bool:
        if name in PINNED_CARDS:
            return False
        return effective_name(name) in lands_set

    def lands_rank_of(name: str) -> int:
        return lands_rank[effective_name(name)]

    # --- Step 2 & 3: Separate pinned vs moveable, sort moveable, merge ---
    moveable_slots = []  # (name, count, raw_line) for cards with ATA data
    for slot in collapsed:
        name = slot[0]
        if in_lands(name):
            moveable_slots.append(slot)

    # Sort moveable by ATA rank (using alias if applicable)
    moveable_slots.sort(key=lambda s: lands_rank_of(s[0]))
    moveable_iter = iter(moveable_slots)

    # Walk collapsed list: keep pinned slots in place, fill others from sorted moveable
    merged = []
    for slot in collapsed:
        name = slot[0]
        if in_lands(name):
            # Moveable: take next from sorted list
            merged.append(next(moveable_iter))
        else:
            # Pinned: keep as-is (ELO position)
            merged.append(slot)

    # --- Step 4 & 5: Expand and renumber ---
    result = []
    rank_counter = 1
    for name, count, raw_line in merged:
        # Extract the template portion after the rank ("|Name|C|CUSTOM")
        pipe_idx = raw_line.index("|")
        template = raw_line[pipe_idx:]  # "|Card Name|C|CUSTOM"

        for _ in range(count):
            result.append(f"#{rank_counter}{template}")
            rank_counter += 1

    return result


def main():
    # rerank.py <baseline> <17lands.csv> <out>
    # rerank.py <baseline> <newest.csv> <older.csv> [...] <out>   (priority order)
    cobra_file = sys.argv[1] if len(sys.argv) > 1 else "AIForgeRankingsELO.txt"
    lands_files = sys.argv[2:-1] if len(sys.argv) > 3 else [sys.argv[2] if len(sys.argv) > 2 else "card-ratings-2026-03-31.csv"]
    output_file = sys.argv[-1] if len(sys.argv) > 3 else "AIForgeRankings.txt"

    cobra_entries = parse_cubecobra(cobra_file)
    lands_order, source = merge_17lands(lands_files)
    result = build_reranked_list(cobra_entries, lands_order)

    with open(output_file, "w", encoding="utf-8") as f:
        for line in result:
            f.write(line + "\n")

    print(f"Wrote {len(result)} cards to {output_file}")
    moveable = sum(1 for name in (e[1] for e in cobra_entries)
                   if name in set(lands_order) or NAME_ALIASES.get(name) in set(lands_order))
    print(f"  {moveable} cards ranked by 17lands ATA, {len(result) - moveable} pinned at ELO")
    cube = {e[1] for e in cobra_entries}
    for fp in lands_files:
        print(f"    from {fp}: {sum(1 for n in cube if source.get(NAME_ALIASES.get(n, n)) == fp)}")


if __name__ == "__main__":
    main()
