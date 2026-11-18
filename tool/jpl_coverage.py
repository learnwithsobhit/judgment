#!/usr/bin/env python3
"""Verify / report Judgement Premier League Season 1 all-play-all coverage.

Default fixture: 14 players, 6 matchdays × (1×6 + 2×4) tables.
Exit 0 if every pair shares a table at least once; else exit 1.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
from typing import Iterable

ROSTER: dict[str, str] = {
    "A": "Upavan",
    "B": "Dharmendra",
    "C": "shobhit",
    "D": "Ankit",
    "E": "Gagan",
    "F": "Arun",
    "G": "Deepak",
    "H": "Anurag",
    "I": "akash",
    "J": "Aadarsh",
    "K": "Chandan",
    "L": "Kapil",
    "M": "ashish",
    "N": "Uday",
}

# Verified covering (greedy search seed 695). Each matchday: big-six, four, four.
FIXTURE: list[list[str]] = [
    # Matchday 1
    ["ABCEHM", "GJKN", "DFIL"],
    # Matchday 2
    ["CGIKLM", "BDHJ", "AEFN"],
    # Matchday 3
    ["CDFJMN", "ABGL", "EHIK"],
    # Matchday 4
    ["ADEFGK", "BCIJ", "HLMN"],
    # Matchday 5
    ["EFGHJL", "AIMN", "BCDK"],
    # Matchday 6
    ["ABFJKN", "CDHL", "EGIM"],
]


def pairs_of(table: str) -> set[frozenset[str]]:
    return {frozenset(p) for p in combinations(table, 2)}


def name(code: str) -> str:
    return ROSTER.get(code, code)


def expand_tables(matchdays: Iterable[list[str]]) -> list[tuple[int, str, tuple[str, ...]]]:
    rows: list[tuple[int, str, tuple[str, ...]]] = []
    for md_i, tables in enumerate(matchdays, start=1):
        labels = ("Big Six", "Orange", "Blue")
        for label, codes in zip(labels, tables, strict=True):
            rows.append((md_i, label, tuple(codes)))
    return rows


def analyze(matchdays: list[list[str]]) -> dict:
    players = sorted(ROSTER)
    all_pairs = {frozenset(p) for p in combinations(players, 2)}
    meet: dict[frozenset[str], int] = {pr: 0 for pr in all_pairs}
    games: Counter[str] = Counter()
    by_player_md: dict[str, list[dict]] = defaultdict(list)

    for md_i, tables in enumerate(matchdays, start=1):
        labels = ("Big Six", "Orange", "Blue")
        seated: set[str] = set()
        for label, table in zip(labels, tables, strict=True):
            codes = list(table)
            if len(set(codes)) != len(codes):
                raise SystemExit(f"duplicate seat on MD{md_i} {label}: {table}")
            seated.update(codes)
            for p in codes:
                games[p] += 1
            for pr in pairs_of(table):
                meet[pr] += 1
            for p in codes:
                opponents = sorted(name(q) for q in codes if q != p)
                by_player_md[p].append(
                    {
                        "matchday": md_i,
                        "table": label,
                        "size": len(codes),
                        "opponents": opponents,
                    }
                )
        if seated != set(players):
            missing = sorted(set(players) - seated)
            extra = sorted(seated - set(players))
            raise SystemExit(
                f"MD{md_i} seat mismatch missing={missing} extra={extra}"
            )

    missing_pairs = sorted(
        tuple(sorted(pr)) for pr, n in meet.items() if n == 0
    )
    hist = Counter(meet.values())
    cards = {}
    for p in players:
        faced = Counter()
        for md in by_player_md[p]:
            # recover codes from names is awkward; recount from fixture
            pass
        for q in players:
            if q == p:
                continue
            faced[q] = meet[frozenset((p, q))]
        still = sorted(name(q) for q, n in faced.items() if n == 0)
        cards[name(p)] = {
            "code": p,
            "games": games[p],
            "matchdays": by_player_md[p],
            "meet_counts": {name(q): faced[q] for q in players if q != p},
            "still_to_face": still,
        }

    return {
        "players": len(players),
        "pairs_total": len(all_pairs),
        "pairs_missing": [f"{name(a)}–{name(b)}" for a, b in missing_pairs],
        "meet_histogram": {str(k): v for k, v in sorted(hist.items())},
        "max_meet": max(meet.values()) if meet else 0,
        "min_meet": min(meet.values()) if meet else 0,
        "games_per_player": {name(p): games[p] for p in players},
        "cards": cards,
        "ok": not missing_pairs,
    }


def markdown_report(data: dict, matchdays: list[list[str]]) -> str:
    lines: list[str] = []
    lines.append("# Judgement Premier League — Season 1 Fixture")
    lines.append("")
    lines.append(
        "All-play-all points series: every pair shares a table at least once. "
        "Each Matchday runs **one 6-seat + two 4-seat** rooms in parallel "
        "(no byes). Medal points: Gold 500 / Silver 100 / Bronze 20."
    )
    lines.append("")
    lines.append("## Roster")
    lines.append("")
    lines.append("| Code | Player |")
    lines.append("|------|--------|")
    for code, player in ROSTER.items():
        lines.append(f"| {code} | {player} |")
    lines.append("")
    lines.append("## Coverage check")
    lines.append("")
    lines.append(f"- Pairs to cover: **{data['pairs_total']}**")
    lines.append(
        f"- Missing pairs: **{len(data['pairs_missing'])}**"
        + (
            f" ({', '.join(data['pairs_missing'])})"
            if data["pairs_missing"]
            else ""
        )
    )
    hist_txt = ", ".join(
        f"{count}× pairs meet {times}"
        for times, count in sorted(
            ((int(k), v) for k, v in data["meet_histogram"].items()),
            key=lambda kv: kv[0],
        )
    )
    lines.append(
        f"- Pair meetings: {hist_txt} "
        f"(min {data['min_meet']}, max {data['max_meet']})"
    )
    lines.append(
        f"- Games per player: all **{next(iter(data['games_per_player'].values()))}**"
        if len(set(data["games_per_player"].values())) == 1
        else f"- Games per player: {data['games_per_player']}"
    )
    lines.append("")
    lines.append("## Fixture sheet")
    lines.append("")
    labels = ("Big Six", "Orange", "Blue")
    for md_i, tables in enumerate(matchdays, start=1):
        lines.append(f"### Matchday {md_i}")
        lines.append("")
        lines.append("| Table | Size | Players |")
        lines.append("|-------|------|---------|")
        for label, codes in zip(labels, tables, strict=True):
            people = ", ".join(name(c) for c in codes)
            lines.append(f"| {label} | {len(codes)} | {people} |")
        lines.append("")

    lines.append("## Per-player cards")
    lines.append("")
    for player, card in sorted(data["cards"].items(), key=lambda kv: kv[1]["code"]):
        lines.append(f"### {player} ({card['code']})")
        lines.append("")
        lines.append(f"Games: **{card['games']}**. Still to face: "
                      + ("*(none — full coverage)*" if not card["still_to_face"]
                         else ", ".join(card["still_to_face"])))
        lines.append("")
        lines.append("| MD | Table | Opponents |")
        lines.append("|----|-------|-----------|")
        for row in card["matchdays"]:
            lines.append(
                f"| {row['matchday']} | {row['table']} ({row['size']}) | "
                f"{', '.join(row['opponents'])} |"
            )
        lines.append("")
        lines.append("Meet counts (how often they share a table):")
        lines.append("")
        meets = ", ".join(
            f"{opp}×{n}" for opp, n in sorted(card["meet_counts"].items(), key=lambda x: (-x[1], x[0]))
        )
        lines.append(meets)
        lines.append("")

    lines.append("## Host runbook")
    lines.append("")
    lines.append("1. **Create tournament** (admin): title e.g. "
                 "`Judgement Premier League — Season 1`, status **Live**.")
    lines.append("2. **Each Matchday**, open **three rooms** and attach each to that tournament:")
    lines.append("   - Room 1 → Big Six (max players 6)")
    lines.append("   - Room 2 → Orange (max players 4)")
    lines.append("   - Room 3 → Blue (max players 4)")
    lines.append("3. Seat only the named players for that table; **no guest substitutes**.")
    lines.append("4. Start all three tables in the same sitting when the squad is ready.")
    lines.append("5. If someone is absent, **reschedule that table** — do not silently replace.")
    lines.append("6. Standings accumulate on the app **Tournament** tab "
                 "(same medal math as Top players).")
    lines.append("7. After Matchday 6, champion = top of tournament standings; "
                 "optionally publish the pair heat-map from this script’s JSON.")
    lines.append("")
    lines.append("## Re-validate")
    lines.append("")
    lines.append("```bash")
    lines.append("python3 tool/jpl_coverage.py")
    lines.append("python3 tool/jpl_coverage.py --json")
    lines.append(
        "python3 tool/jpl_coverage.py "
        "--write-html docs/marketing/jpl_season1_fixture.html"
    )
    lines.append("```")
    lines.append("")
    lines.append(
        "Shareable HTML preview: "
        "[jpl_season1_fixture.html](jpl_season1_fixture.html)"
    )
    lines.append("")
    return "\n".join(lines)


def preview_payload(data: dict, matchdays: list[list[str]]) -> dict:
    labels = ("Big Six", "Orange", "Blue")
    return {
        "roster": [{"code": c, "name": n} for c, n in ROSTER.items()],
        "matchdays": [
            {
                "n": md_i,
                "tables": [
                    {
                        "label": label,
                        "size": len(codes),
                        "players": [name(c) for c in codes],
                        "codes": list(codes),
                    }
                    for label, codes in zip(labels, tables, strict=True)
                ],
            }
            for md_i, tables in enumerate(matchdays, start=1)
        ],
        "cards": data["cards"],
        "coverage": {
            "pairs": data["pairs_total"],
            "missing": len(data["pairs_missing"]),
            "hist": data["meet_histogram"],
            "games": next(iter(data["games_per_player"].values()), 0),
        },
    }


def write_html_preview(path: str, data: dict, matchdays: list[list[str]]) -> None:
    root = Path(__file__).resolve().parent
    template = (root / "jpl_fixture_preview.html.tpl").read_text(encoding="utf-8")
    payload = json.dumps(preview_payload(data, matchdays), ensure_ascii=False)
    # Keep </script> from breaking out of the JSON script tag.
    safe = payload.replace("<", "\\u003c")
    html = template.replace("__JPL_DATA__", safe)
    Path(path).write_text(html, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable coverage + per-player cards",
    )
    parser.add_argument(
        "--write-md",
        metavar="PATH",
        help="Write the shareable markdown fixture sheet to PATH",
    )
    parser.add_argument(
        "--write-html",
        metavar="PATH",
        help="Write the shareable HTML fixture preview to PATH",
    )
    args = parser.parse_args()

    data = analyze(FIXTURE)
    if args.json:
        print(json.dumps(data, indent=2, sort_keys=True))
    elif not args.write_md and not args.write_html:
        status = "OK" if data["ok"] else "FAIL"
        print(f"coverage {status}: missing={len(data['pairs_missing'])} "
              f"meet_hist={data['meet_histogram']} "
              f"games={data['games_per_player']}")
        if data["pairs_missing"]:
            print("missing:", ", ".join(data["pairs_missing"]))

    if args.write_md:
        text = markdown_report(data, FIXTURE)
        with open(args.write_md, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.write_md}")

    if args.write_html:
        write_html_preview(args.write_html, data, FIXTURE)
        print(f"wrote {args.write_html}")

    raise SystemExit(0 if data["ok"] else 1)


if __name__ == "__main__":
    main()
