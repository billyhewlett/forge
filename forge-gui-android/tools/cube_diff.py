"""
Describe AIForge cube swaps: old card (rank) -> new card (rank), with a comparable
card already in the cube for each new card.

    python forge-gui-android/tools/cube_diff.py                 # HEAD vs working tree
    python forge-gui-android/tools/cube_diff.py --from adc0616 --to HEAD

Compares forge-gui/res/cube/AIForge.dck and forge-gui/res/draft/AIForgeRankings.txt at
two points (a git revision, or the working tree). Run it after update_cube.py + rerank.py
and paste the output into the commit message / CUBE_CHANGELOG.md.

- Old cards are ranked by the OLD rankings, new and comparable cards by the NEW ones.
- Pairing old -> new: same exact colors first, then same color group, then whatever is
  left (by rank). Color groups: single color W/U/B/R/G, Multicolor, Colorless.
- "Comparable" = a card that was in the cube before this change and stays in it, in the
  same color group (same exact colors preferred for multicolor), same broad type preferred
  (creature, planeswalker, instant/sorcery, artifact, enchantment, land), nearest in rank.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rerank import FLAVOR_NAMES  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CUBE = "forge-gui/res/cube/AIForge.dck"
RANKINGS = "forge-gui/res/draft/AIForgeRankings.txt"
CARDS = os.path.join(ROOT, "forge-gui", "res", "cardsfolder")
GROUP_NAMES = {"W": "white", "U": "blue", "B": "black", "R": "red", "G": "green",
               "M": "multicolor", "C": "colorless"}
TYPE_ORDER = ["Land", "Creature", "Planeswalker", "Battle", "Instant", "Sorcery",
              "Artifact", "Enchantment", "Conspiracy"]


def read(rev, path):
    if rev is None:
        with open(os.path.join(ROOT, path), encoding="utf-8-sig") as f:
            return f.read()
    out = subprocess.run(["git", "-C", ROOT, "show", f"{rev}:{path}"],
                         capture_output=True, check=True)
    return out.stdout.decode("utf-8-sig")


def cube_names(text):
    names = [l.split(" ", 1)[1].split("|")[0] for l in text.splitlines() if l[:1].isdigit()]
    return [FLAVOR_NAMES.get(n, n) for n in names]


def rankings(text):
    ranks = {}
    for l in text.splitlines():
        if l.startswith("#"):
            rank, name = l.split("|")[:2]
            ranks[name] = int(rank[1:])
    return ranks


def card_info(names):
    """name -> (frozenset colors, broad type) from the card script's front face."""
    wanted, info = set(names), {}
    for dirpath, _, files in os.walk(CARDS):
        for fn in files:
            if not fn.endswith(".txt"):
                continue
            with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                front = f.read().split("\nALTERNATE")[0]
            m = re.search(r"^Name:(.+)$", front, re.M)
            if not m or m.group(1).strip() not in wanted:
                continue
            cost = re.search(r"^ManaCost:(.+)$", front, re.M)
            explicit = re.search(r"^Colors:(.+)$", front, re.M)
            if explicit:
                colors = {c[0].upper() if c != "blue" else "U" for c in explicit.group(1).split(",")}
                colors = {c for c in colors if c in "WUBRG"}
            else:
                colors = set(re.findall(r"[WUBRG]", cost.group(1))) if cost else set()
            types = re.search(r"^Types:(.+)$", front, re.M).group(1).split()
            broad = next((t for t in TYPE_ORDER if t in types), types[-1])
            if broad == "Sorcery":
                broad = "Instant"  # instant/sorcery = one bucket
            info[m.group(1).strip()] = (frozenset(colors), broad)
    return info


def group(colors):
    return next(iter(colors)) if len(colors) == 1 else ("M" if colors else "C")


def pair(removed, added, info, old_rank, new_rank):
    removed = sorted(removed, key=lambda n: old_rank.get(n, 999))
    added = sorted(added, key=lambda n: new_rank.get(n, 999))
    pairs = []
    for match in (lambda a, b: info[a][0] == info[b][0],
                  lambda a, b: group(info[a][0]) == group(info[b][0]),
                  lambda a, b: True):
        for r in list(removed):
            a = next((x for x in added if match(r, x)), None)
            if a:
                pairs.append((r, a))
                removed.remove(r)
                added.remove(a)
    return pairs


def comparable(card, pool, info, new_rank):
    colors, broad = info[card]
    g = group(colors)
    same_group = [c for c in pool if group(info[c][0]) == g]
    if not same_group:
        return None
    exact = [c for c in same_group if info[c][0] == colors]
    candidates = exact if g == "M" and exact else same_group
    typed = [c for c in candidates if info[c][1] == broad]
    candidates = typed or candidates
    return min(candidates, key=lambda c: (abs(new_rank[c] - new_rank[card]), new_rank[c]))


def describe(card, info):
    colors, broad = info[card]
    g = group(colors)
    label = GROUP_NAMES[g] if g != "M" else "".join(c for c in "WUBRG" if c in colors)
    return f"{label} {broad.lower() if broad != 'Instant' else 'instant/sorcery'}"


def main():
    sys.stdout.reconfigure(encoding="utf-8")  # Windows console default mangles e.g. "dûm"
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="rev_from", default="HEAD")
    ap.add_argument("--to", dest="rev_to", default=None, help="git rev; default = working tree")
    args = ap.parse_args()

    old_cube = cube_names(read(args.rev_from, CUBE))
    new_cube = cube_names(read(args.rev_to, CUBE))
    old_rank = rankings(read(args.rev_from, RANKINGS))
    new_rank = rankings(read(args.rev_to, RANKINGS))
    removed = [c for c in old_cube if c not in set(new_cube)]
    added = [c for c in new_cube if c not in set(old_cube)]
    if not removed and not added:
        print("No cube swaps.")
        return
    info = card_info(set(old_cube) | set(new_cube))
    missing = [c for c in removed + added if c not in info]
    if missing:
        sys.exit("No card script found for: " + "; ".join(missing))
    kept = [c for c in new_cube if c in set(old_cube)]

    print(f"Cube swaps ({len(removed)} out, {len(added)} in). Old ranks from the old rankings, "
          "new and comparable ranks from the new rankings.\n")
    pairs = pair(removed, added, info, old_rank, new_rank)
    for r, a in sorted(pairs, key=lambda p: new_rank.get(p[1], 999)):
        comp = comparable(a, kept, info, new_rank)
        comp_txt = f"; similar to {comp} (#{new_rank[comp]})" if comp else ""
        print(f"- {r} (#{old_rank.get(r, '?')}) -> {a} (#{new_rank.get(a, '?')}), "
              f"{describe(a, info)}{comp_txt}")
    paired_r = {r for r, _ in pairs}
    paired_a = {a for _, a in pairs}
    for r in removed:
        if r not in paired_r:
            print(f"- {r} (#{old_rank.get(r, '?')}) removed, no replacement")
    for a in added:
        if a not in paired_a:
            comp = comparable(a, kept, info, new_rank)
            comp_txt = f"; similar to {comp} (#{new_rank[comp]})" if comp else ""
            print(f"- added {a} (#{new_rank.get(a, '?')}), {describe(a, info)}{comp_txt}")


if __name__ == "__main__":
    main()
