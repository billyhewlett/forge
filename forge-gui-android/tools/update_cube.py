"""
Apply a CubeCobra .dck export to forge-gui/res/cube/AIForge.dck.

    python forge-gui-android/tools/update_cube.py "C:/Users/billy/Downloads/AIForge (4).dck"

Takes from the export: which cards are in the cube, and their order (CubeCobra's
ELO order, worst first). Keeps from the repo: the set code of every card that is
already in the cube — those printings were hand-fixed for art, and the CubeCobra
export silently reverts them. Only newly added cards use the export's set code.

Then reports adds/removes and any card name with no `Name:` match in cardsfolder
(a flavor name that needs a FLAVOR_NAMES entry in rerank.py, or an unimplemented card).
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CUBE = os.path.join(ROOT, "forge-gui", "res", "cube", "AIForge.dck")
CARDS = os.path.join(ROOT, "forge-gui", "res", "cardsfolder")


def read_lines(path):
    with open(path, encoding="utf-8-sig") as f:
        return [l.rstrip("\r\n") for l in f]


def card_name(line):
    return line.split(" ", 1)[1].split("|")[0]


def all_card_names():
    names = set()
    for dirpath, _, files in os.walk(CARDS):
        for fn in files:
            if fn.endswith(".txt"):
                with open(os.path.join(dirpath, fn), encoding="utf-8") as f:
                    names.update(l[5:].strip() for l in f if l.startswith("Name:"))
    return names


def main():
    export = read_lines(sys.argv[1])
    repo = read_lines(CUBE)
    repo_by_name = {card_name(l): l for l in repo if l[:1].isdigit()}

    out, added = [], []
    for line in export:
        if line[:1].isdigit():
            name = card_name(line)
            if name in repo_by_name:
                out.append(repo_by_name[name])
            else:
                out.append(line)
                added.append(line)
        else:
            out.append(line)
    export_names = {card_name(l) for l in export if l[:1].isdigit()}
    removed = sorted(n for n in repo_by_name if n not in export_names)

    # UTF-8, no BOM, LF line endings (required by Forge's cube loader).
    with open(CUBE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")

    print(f"Wrote {sum(1 for l in out if l[:1].isdigit())} cards to {CUBE}")
    print(f"Added ({len(added)}):   " + "; ".join(added))
    print(f"Removed ({len(removed)}): " + "; ".join(removed))
    known = all_card_names()
    missing = sorted(n for n in export_names if n not in known)
    if missing:
        print("No Name: match in cardsfolder (flavor name -> add to FLAVOR_NAMES in rerank.py, "
              "or card not implemented in Forge): " + "; ".join(missing))


if __name__ == "__main__":
    main()
