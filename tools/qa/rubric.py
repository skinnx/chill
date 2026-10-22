#!/usr/bin/env python3
"""Aggregate the 3-rater visual rubric (Art Bible §11.1-11.2, synthesis D13/V7; docs/QA.md §5).

Usage:
    python3 -I tools/qa/rubric.py template --rater NAME --build LABEL [--set DIR] > rater_NAME.json
    python3 -I tools/qa/rubric.py score qa/reports/<build>/rater_*.json [--json OUT] [--require LEVEL]
    python3 -I tools/qa/rubric.py --selftest

Each rater fills in one JSON file on their own (never after seeing another rater's scores):
integer scores 1-10 for the ten criteria below, plus optional notes. `score` checks the files
(same build, distinct raters, every criterion scored), takes the per-criterion MEDIAN (Art Bible
§11.2) and MEAN (docs/TEAM.md gate 3 says "average"), flags any criterion whose spread
(max - min) is above 2 points for a review discussion, and applies the thresholds below to both;
the verdict is the LOWER of the two levels, so it satisfies both documents:

    prototype      total < 60
    alpha          60-69 (no Art Bible name; below soft-launch)
    soft-launch    70-79, or >= 80 without the per-criterion floors
    ship           total >= 80, every criterion >= 7, and #1, #6, #8 >= 8
    feature        total >= 88 and every criterion >= 8
    R1 gate        #3, #5, #6, #9 >= 7 (look spike, before any content work; reported separately)

A verdict needs at least 3 raters; with fewer the report says so and `--require` always fails.
`--require` (r1 | soft-launch | ship | feature) sets the exit code: 0 when met, 1 when not.
Standard library only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import statistics
import sys
from pathlib import Path

# Art Bible §11.1 criteria (key = rubric number).
CRITERIA: dict[str, str] = {
    "1": "Value structure & focal hierarchy",
    "2": "Palette harmony",
    "3": "Edge quality & AA",
    "4": "Depth & atmosphere",
    "5": "Lighting coherence",
    "6": "Motion quality",
    "7": "Touch feedback",
    "8": "UI clarity & accessibility",
    "9": "Consistency",
    "10": "Polish & 'Today tab' test",
}
SCORE_MIN = 1
SCORE_MAX = 10
MIN_RATERS = 3
REVIEW_SPREAD = 2
PROTOTYPE_BELOW = 60
SOFT_LAUNCH_FROM = 70
SHIP_TOTAL = 80
SHIP_FLOOR = 7
SHIP_KEY_FLOOR = 8
SHIP_KEY_CRITERIA = ("1", "6", "8")
FEATURE_TOTAL = 88
FEATURE_FLOOR = 8
R1_CRITERIA = ("3", "5", "6", "9")
R1_FLOOR = 7
LEVELS = ("prototype", "alpha", "soft-launch", "ship", "feature")


def template(rater: str, build: str, capture_set: str) -> dict:
    return {
        "rater": rater,
        "build": build,
        "date": dt.date.today().isoformat(),
        "capture_set": capture_set,
        "viewed_at_1to1": True,
        "scores": {k: None for k in CRITERIA},
        "notes": {k: "" for k in CRITERIA},
        "criteria": CRITERIA,
    }


def _load(path: Path) -> dict:
    doc = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or not isinstance(doc.get("scores"), dict):
        raise ValueError(f"{path}: not a rater file (no 'scores' object)")
    rater = str(doc.get("rater", "")).strip()
    if not rater:
        raise ValueError(f"{path}: 'rater' is empty")
    scores: dict[str, int] = {}
    for key in CRITERIA:
        v = doc["scores"].get(key)
        if isinstance(v, bool) or not isinstance(v, int) or not SCORE_MIN <= v <= SCORE_MAX:
            raise ValueError(f"{path}: criterion {key} ({CRITERIA[key]}) needs an integer "
                             f"{SCORE_MIN}-{SCORE_MAX}, got {v!r}")
        scores[key] = v
    extra = sorted(set(doc["scores"]) - set(CRITERIA))
    if extra:
        raise ValueError(f"{path}: unknown criteria {extra}")
    return {"file": str(path), "rater": rater, "build": str(doc.get("build", "")),
            "viewed_at_1to1": bool(doc.get("viewed_at_1to1", False)), "scores": scores}


def level_for(total: float, medians: dict[str, float]) -> str:
    if total >= FEATURE_TOTAL and all(v >= FEATURE_FLOOR for v in medians.values()):
        return "feature"
    if (total >= SHIP_TOTAL and all(v >= SHIP_FLOOR for v in medians.values())
            and all(medians[k] >= SHIP_KEY_FLOOR for k in SHIP_KEY_CRITERIA)):
        return "ship"
    if total >= SOFT_LAUNCH_FROM:
        return "soft-launch"
    if total >= PROTOTYPE_BELOW:
        return "alpha"
    return "prototype"


def aggregate(raters: list[dict]) -> dict:
    problems: list[str] = []
    names = [r["rater"].casefold() for r in raters]
    if len(set(names)) != len(names):
        problems.append("the same rater appears twice")
    builds = sorted({r["build"] for r in raters})
    if len(builds) > 1:
        problems.append(f"files rate different builds: {builds}")
    if len(raters) < MIN_RATERS:
        problems.append(f"{len(raters)} rater(s); the protocol needs {MIN_RATERS} independent raters")
    not_1to1 = [r["rater"] for r in raters if not r["viewed_at_1to1"]]
    if not_1to1:
        problems.append(f"not scored at 1:1 (Art Bible §11.2): {not_1to1}")
    medians: dict[str, float] = {}
    means: dict[str, float] = {}
    criteria = []
    review = []
    for key, name in CRITERIA.items():
        vals = [r["scores"][key] for r in raters]
        med = float(statistics.median(vals))
        spread = max(vals) - min(vals)
        medians[key] = med
        means[key] = round(statistics.fmean(vals), 2)
        row = {"criterion": int(key), "name": name, "scores": vals, "median": med, "mean": means[key],
               "spread": spread, "review": spread > REVIEW_SPREAD}
        criteria.append(row)
        if row["review"]:
            review.append(int(key))
    total = sum(medians.values())
    total_mean = round(sum(means.values()), 2)
    level_median = level_for(total, medians)
    level_mean = level_for(total_mean, means)
    level = min(level_median, level_mean, key=LEVELS.index)
    r1 = all(min(medians[k], means[k]) >= R1_FLOOR for k in R1_CRITERIA)
    floor = {k: min(medians[k], means[k]) for k in CRITERIA}
    total_floor = min(total, total_mean)
    blockers = []
    if level not in ("ship", "feature"):
        if total_floor < SHIP_TOTAL:
            blockers.append(f"total {total_floor:g} < {SHIP_TOTAL}")
        blockers += [f"#{k} {floor[k]:g} < {SHIP_FLOOR}" for k in CRITERIA if floor[k] < SHIP_FLOOR]
        blockers += [f"#{k} {floor[k]:g} < {SHIP_KEY_FLOOR}" for k in SHIP_KEY_CRITERIA
                     if SHIP_FLOOR <= floor[k] < SHIP_KEY_FLOOR]
    valid = not problems
    return {
        "tool": "tools/qa/rubric.py",
        "build": builds[0] if len(builds) == 1 else builds,
        "raters": [r["rater"] for r in raters],
        "valid": valid,
        "problems": problems,
        "criteria": criteria,
        "total": total,
        "total_mean": total_mean,
        "level_median": level_median,
        "level_mean": level_mean,
        "level": level if valid else None,
        "level_if_valid": level,
        "r1_gate": r1,
        "ship_blockers": blockers,
        "review_criteria": review,
    }


def meets(report: dict, need: str) -> bool:
    if not report["valid"]:
        return False
    if need == "r1":
        return bool(report["r1_gate"])
    return LEVELS.index(report["level"]) >= LEVELS.index(need)


def selftest() -> int:
    ok = True

    def rater(name: str, scores: list[int]) -> dict:
        return {"file": name, "rater": name, "build": "b1", "viewed_at_1to1": True,
                "scores": {str(i + 1): s for i, s in enumerate(scores)}}

    def expect(label: str, cond: bool, detail: object) -> None:
        nonlocal ok
        ok = ok and cond
        print(("PASS " if cond else "FAIL ") + label + "  " + json.dumps(detail))

    ship = [rater("a", [8, 8, 8, 8, 8, 8, 8, 8, 8, 8]), rater("b", [8, 7, 8, 8, 8, 9, 8, 8, 8, 8]),
            rater("c", [9, 8, 8, 8, 7, 8, 8, 9, 8, 8])]
    r = aggregate(ship)
    expect("all-8 panel ships (80, floors met)", r["level"] == "ship" and r["total"] == 80, r["total"])
    low_key = [rater(n, [9, 9, 9, 9, 9, 7, 9, 9, 9, 9]) for n in "abc"]
    r = aggregate(low_key)
    expect("#6 at 7 blocks ship despite total 88", r["level"] == "soft-launch" and r["total"] == 88, r["ship_blockers"])
    skew = [rater("a", [8] * 10), rater("b", [8] * 10), rater("c", [8, 8, 8, 8, 8, 6, 8, 8, 8, 8])]
    r = aggregate(skew)
    expect("median ships but mean #6 7.33 < 8 holds it back (lower level wins)",
           r["level_median"] == "ship" and r["level"] == "soft-launch", [r["level_median"], r["level_mean"]])
    proto = [rater(n, [5] * 10) for n in "abc"]
    expect("all-5 is prototype", aggregate(proto)["level"] == "prototype", aggregate(proto)["total"])
    spread = [rater("a", [8] * 10), rater("b", [8] * 10), rater("c", [8, 8, 8, 8, 8, 8, 8, 8, 8, 4])]
    r = aggregate(spread)
    expect("spread > 2 flags a review, median ignores the outlier", r["review_criteria"] == [10]
           and r["criteria"][9]["median"] == 8.0, r["review_criteria"])
    two = aggregate(ship[:2])
    expect("two raters give no verdict", not two["valid"] and two["level"] is None and not meets(two, "r1"),
           two["problems"])
    r1 = [rater(n, [6, 6, 7, 6, 7, 7, 6, 6, 7, 6]) for n in "abc"]
    expect("R1 gate is independent of the total", aggregate(r1)["r1_gate"] and meets(aggregate(r1), "r1"),
           aggregate(r1)["total"])
    feature = [rater(n, [9] * 10) for n in "abc"]
    expect("all-9 is feature-worthy", aggregate(feature)["level"] == "feature", aggregate(feature)["total"])
    print("selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("template", help="print an empty rater file")
    t.add_argument("--rater", required=True)
    t.add_argument("--build", required=True, help="git SHA or build label being rated")
    t.add_argument("--set", default="qa/out/set", help="capture set the rater looked at")
    s = sub.add_parser("score", help="aggregate rater files")
    s.add_argument("files", nargs="+", type=Path)
    s.add_argument("--json", type=Path, help="also write the report here")
    s.add_argument("--require", choices=("r1",) + LEVELS[2:], help="exit 1 unless this level is met")
    args = ap.parse_args(argv)
    if args.cmd == "template":
        print(json.dumps(template(args.rater, args.build, args.set), indent=2, ensure_ascii=False))
        return 0
    try:
        raters = [_load(p) for p in args.files]
    except (OSError, ValueError) as e:
        print(f"rubric: {e}", file=sys.stderr)
        return 2
    report = aggregate(raters)
    text = json.dumps(report, indent=2, ensure_ascii=False)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(text + "\n", encoding="utf-8")
    print(text)
    print(f"rubric: total {report['total']:g}, level {report['level'] or 'n/a (' + '; '.join(report['problems']) + ')'}, "
          f"R1 {'met' if report['r1_gate'] else 'not met'}, review {report['review_criteria'] or 'none'}",
          file=sys.stderr)
    if args.require:
        return 0 if meets(report, args.require) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
