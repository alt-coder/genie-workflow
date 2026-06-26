#!/usr/bin/env python3
"""
Budget Tracker v7 — $50/goal gate + phase tracking + reconciliation
Usage:
  budget_tracker.py init <goal_id> [--budget 50.0]
  budget_tracker.py check <goal_id> --estimate 5.0
  budget_tracker.py record <goal_id> --cost 2.50 [--phase implement]
  budget_tracker.py report [<goal_id>]
"""

import sys, json, os, datetime, argparse

DATA_DIR = os.path.expanduser("~/.hermes/staging")
DEFAULT_BUDGET = 50.0
RECONCILIATION_INTERVAL = 300  # 5 min


def _data_file(goal_id):
    return os.path.join(DATA_DIR, goal_id, "budget.json")


def _ensure_dir(goal_id):
    os.makedirs(os.path.join(DATA_DIR, goal_id), exist_ok=True)


def init_goal(goal_id, budget=DEFAULT_BUDGET):
    _ensure_dir(goal_id)
    data = {
        "goal_id": goal_id,
        "budget": float(budget),
        "spent": 0.0,
        "phases": {},
        "estimates": {},
        "created": datetime.datetime.now().isoformat(),
        "last_reconciled": None,
    }
    with open(_data_file(goal_id), "w") as f:
        json.dump(data, f, indent=2)
    print(f"[BUDGET] Initialized {goal_id} with ${budget:.2f}")
    return True


def check_budget(goal_id, estimate):
    path = _data_file(goal_id)
    if not os.path.exists(path):
        print(f"[BUDGET] ERROR: Goal {goal_id} not initialized", file=sys.stderr)
        return False
    with open(path) as f:
        data = json.load(f)
    remaining = data["budget"] - data["spent"]
    if estimate > remaining:
        print(f"[BUDGET] BLOCKED: estimate ${estimate:.2f} > remaining ${remaining:.2f}")
        return False
    print(f"[BUDGET] OK: ${estimate:.2f} approved. Remaining: ${remaining:.2f}")
    return True


def record_cost(goal_id, cost, phase=None):
    path = _data_file(goal_id)
    with open(path) as f:
        data = json.load(f)
    data["spent"] += float(cost)
    if phase:
        data["phases"][phase] = data["phases"].get(phase, 0.0) + float(cost)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"[BUDGET] Recorded ${cost:.2f} for {goal_id} (phase: {phase or 'unknown'})")


def report(goal_id=None):
    if goal_id:
        path = _data_file(goal_id)
        if not os.path.exists(path):
            print(f"No budget data for {goal_id}")
            return
        with open(path) as f:
            data = json.load(f)
        remaining = data["budget"] - data["spent"]
        pct = (data["spent"] / data["budget"]) * 100 if data["budget"] > 0 else 0
        print(f"\nGoal: {goal_id}")
        print(f"  Budget:   ${data['budget']:.2f}")
        print(f"  Spent:    ${data['spent']:.2f} ({pct:.1f}%)")
        print(f"  Remaining: ${remaining:.2f}")
        print(f"  Phases:")
        for phase, cost in sorted(data["phases"].items()):
            print(f"    {phase}: ${cost:.2f}")
        return

    # Report all goals
    print("\n=== All Goals Budget Report ===")
    total_budget = 0.0
    total_spent = 0.0
    for root, dirs, files in os.walk(DATA_DIR):
        for d in dirs:
            bf = os.path.join(root, d, "budget.json")
            if os.path.exists(bf):
                with open(bf) as f:
                    data = json.load(f)
                remaining = data["budget"] - data["spent"]
                pct = (data["spent"] / data["budget"]) * 100 if data["budget"] > 0 else 0
                print(f"  {data['goal_id']}: ${data['spent']:.2f} / ${data['budget']:.2f} ({pct:.1f}%)")
                total_budget += data["budget"]
                total_spent += data["spent"]
    print(f"\n  TOTAL: ${total_spent:.2f} / ${total_budget:.2f}")


def reconcile(goal_id):
    """Post-hoc reconciliation: estimate vs actual"""
    path = _data_file(goal_id)
    with open(path) as f:
        data = json.load(f)
    print(f"\n[RECONCILE] {goal_id}")
    for phase, actual in data["phases"].items():
        est = data["estimates"].get(phase, 0.0)
        delta = actual - est
        if abs(delta) > est * 0.3:
            print(f"  {phase}: estimate=${est:.2f} actual=${actual:.2f} delta={delta:+.2f} ⚠️")
        else:
            print(f"  {phase}: estimate=${est:.2f} actual=${actual:.2f} delta={delta:+.2f}")
    data["last_reconciled"] = datetime.datetime.now().isoformat()
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def raise_ceiling(goal_id, pct=25.0, reason="complexity"):
    """Raise budget ceiling by pct% — triggered by complexity review (Phase 4b)."""
    path = _data_file(goal_id)
    if not os.path.exists(path):
        print(f"[BUDGET] ERROR: Goal {goal_id} not initialized", file=sys.stderr)
        return False
    with open(path) as f:
        data = json.load(f)
    old = data["budget"]
    increase = old * (pct / 100.0)
    data["budget"] = old + increase
    data.setdefault("ceiling_raises", []).append({
        "from": old, "to": data["budget"], "pct": pct,
        "reason": reason, "at": datetime.datetime.now().isoformat(),
    })
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"[BUDGET] Ceiling raised {pct:.0f}% (${old:.2f} → ${data['budget']:.2f}) reason: {reason}")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Budget tracker for Genie Pipeline v7")
    sub = parser.add_subparsers(dest="cmd")

    p_init = sub.add_parser("init")
    p_init.add_argument("goal_id")
    p_init.add_argument("--budget", type=float, default=DEFAULT_BUDGET)

    p_check = sub.add_parser("check")
    p_check.add_argument("goal_id")
    p_check.add_argument("--estimate", type=float, required=True)

    p_record = sub.add_parser("record")
    p_record.add_argument("goal_id")
    p_record.add_argument("--cost", type=float, required=True)
    p_record.add_argument("--phase")

    p_report = sub.add_parser("report")
    p_report.add_argument("goal_id", nargs="?")

    p_reconcile = sub.add_parser("reconcile")
    p_reconcile.add_argument("goal_id")

    p_raise = sub.add_parser("raise-ceiling")
    p_raise.add_argument("goal_id")
    p_raise.add_argument("--pct", type=float, default=25.0)
    p_raise.add_argument("--reason", default="complexity")

    args = parser.parse_args()

    if args.cmd == "init":
        sys.exit(0 if init_goal(args.goal_id, args.budget) else 1)
    elif args.cmd == "check":
        sys.exit(0 if check_budget(args.goal_id, args.estimate) else 1)
    elif args.cmd == "record":
        record_cost(args.goal_id, args.cost, args.phase)
    elif args.cmd == "report":
        report(args.goal_id)
    elif args.cmd == "reconcile":
        reconcile(args.goal_id)
    elif args.cmd == "raise-ceiling":
        raise_ceiling(args.goal_id, args.pct, args.reason)
    else:
        parser.print_help()
