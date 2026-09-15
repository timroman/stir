#!/usr/bin/env python3
"""
auto sensitivity — the reference implementation of docs/spec/stir.md part nine,
decisions 60–74.

every rule here is a rule in the spec, with the same names and the same
constants. the swift evaluator's unit tests take their exact expected values
from `worked examples` below, and its seeded simulation test takes its bounds
from `operating characteristics`. change a constant here and in the spec
together, or not at all.

run: python3 tools/auto-sensitivity-sim.py
"""
import math
import random

# ---------------------------------------------------------------------------
# constants (stir.md decisions 63, 64, 65, 68)

LADDER = [0.15, 0.325, 0.5, 0.675, 0.85, 1.0]   # sensitivityValue per step
START_STEP = 2                                   # medium

OK_LOW = 1.05    # detections per hour of listening: half De Koninck's 2.1 position shifts/hr at 65–80
OK_HIGH = 18.0   # top of Montini's normal range for the last third of the night (median 11, IQR 7–18)
MARGIN = 3.0
TOO_LOW = OK_LOW / MARGIN     # 0.35/hr: stir is missing the sleeper
TOO_HIGH = OK_HIGH * MARGIN   # 54/hr: stir is hearing the room

ALPHA, BETA = 0.05, 0.10
ACCEPT_PROBLEM = math.log((1 - BETA) / ALPHA)   # 2.8904
ACCEPT_OK = math.log(BETA / (1 - ALPHA))        # -2.2513
CALIBRATION_NIGHT_CAP = 60
WATCH_H_TOO_SENSITIVE = 5.5
WATCH_H_NOT_SENSITIVE = 4.5

# ---------------------------------------------------------------------------
# one night's evidence (decision 62)

def evidence(night):
    """(detected, hours) or None. night: dict with listening_started (h), trigger, alarm_fired (h),
    up_by (h), ended (h), ending. times are hours on one clock."""
    if night.get("listening_started") is None:
        return None
    trigger = night["trigger"]
    if trigger == "sound":
        end, detected = night["alarm_fired"], True
    elif trigger == "motion":
        end, detected = night["alarm_fired"], False
    elif trigger == "upBy":
        end, detected = night["up_by"], False
    else:  # none: ended by hand inside the window, before the alarm
        end, detected = night["ended"], False
    return detected, max(0.0, end - night["listening_started"])

def llr(detected, hours, r1, r0):
    return (math.log(r1 / r0) if detected else 0.0) - (r1 - r0) * hours

def llr_too_sensitive(e):  return llr(*e, TOO_HIGH, OK_HIGH)
def llr_not_sensitive(e):  return llr(*e, TOO_LOW, OK_LOW)

# ---------------------------------------------------------------------------
# the evaluator (decisions 64–69)

def fresh_state(step=START_STEP):
    return dict(step=step, max_step=len(LADDER) - 1, phase="settling",
                since=0, question_closed=False)

def sprt(values):
    s = 0.0
    for v in values:
        s += v
        if s >= ACCEPT_PROBLEM: return "problem"
        if s <= ACCEPT_OK: return "ok"
    return None

def cusum_fires(values, h):
    s = 0.0
    for v in values:
        s = max(0.0, s + v)
        if s >= h: return True
    return False

def evaluate(state, nights, now_index):
    """returns (state, action) with action in none | step_up | ask | settle.
    nights: list of (index, step, evidence) for clean runs, oldest first."""
    ev = [e for (i, step, e) in nights
          if i >= state["since"] and step == state["step"] and e is not None]
    if not ev:
        return state, "none"
    s = dict(state)
    if s["phase"] == "settling":
        too = "ok" if s["question_closed"] else sprt([llr_too_sensitive(e) for e in ev])
        low = sprt([llr_not_sensitive(e) for e in ev])
        if low == "problem" and s["step"] >= s["max_step"]:
            low = "ok"
        if too == "problem":
            s["question_closed"] = True
            if s["step"] > 0:
                return s, "ask"
            too = "ok"   # the lowest step: yes could change nothing, so nothing is asked
        if low == "problem":
            return step_to(s, s["step"] + 1, now_index), "step_up"
        if (too == "ok" and low == "ok") or len(ev) >= CALIBRATION_NIGHT_CAP:
            s["phase"], s["since"] = "settled", now_index + 1
            return s, "settle"
        return s, "none"
    # settled
    if not s["question_closed"] and cusum_fires([llr_too_sensitive(e) for e in ev], WATCH_H_TOO_SENSITIVE):
        s["question_closed"] = True
        if s["step"] > 0:
            return s, "ask"
    if s["step"] < s["max_step"] and cusum_fires([llr_not_sensitive(e) for e in ev], WATCH_H_NOT_SENSITIVE):
        return step_to(s, s["step"] + 1, now_index), "step_up"
    return s, "none"

def step_to(s, step, now_index):
    s = dict(s)
    s.update(step=step, phase="settling", since=now_index + 1, question_closed=False)
    return s

def answer(state, yes, now_index):
    """decision 67: yes steps down and caps the ladder there; no changes nothing."""
    if not yes or state["step"] == 0:
        return state
    s = step_to(state, state["step"] - 1, now_index)
    s["max_step"] = s["step"]
    return s

# ---------------------------------------------------------------------------
# simulated nights

def simulated_night(rate_per_hour, window_minutes, rng):
    """listening starts at 0; the first detection is exponential; none by up by falls back."""
    nightly = rate_per_hour * math.exp(rng.gauss(-0.125, 0.5))
    hours = window_minutes / 60
    t = rng.expovariate(nightly) if nightly > 0 else math.inf
    if t < hours:
        return dict(listening_started=0.0, trigger="sound", alarm_fired=t, up_by=hours, ended=t + 0.05)
    return dict(listening_started=0.0, trigger="upBy", alarm_fired=hours, up_by=hours, ended=hours + 0.05)

def run_person(rates_by_step, answers_yes, rng, nights=120, window=lambda r: 30):
    state = fresh_state()
    history, asked, steps = [], 0, 0
    for n in range(nights):
        night = simulated_night(rates_by_step[state["step"]], window(rng), rng)
        history.append((n, state["step"], evidence(night)))
        state, action = evaluate(state, history, n)
        if action == "ask":
            asked += 1
            state = answer(state, answers_yes, n)
        elif action == "step_up":
            steps += 1
    return state, asked, steps

# ---------------------------------------------------------------------------

def worked_examples():
    print("WORKED EXAMPLES (exact; the swift unit tests assert these)")
    print(f"  accept a problem at  {ACCEPT_PROBLEM:.4f}")
    print(f"  accept ok at         {ACCEPT_OK:.4f}")
    def nights_until(night_fn, test, limit=200):
        s = 0.0
        for n in range(1, limit):
            s += test(night_fn())
            if s >= ACCEPT_PROBLEM: return n, "problem", s
            if s <= ACCEPT_OK: return n, "ok", s
        return None
    cases = [
        ("30-minute nights, no detection: not-sensitive side", lambda: (False, 0.5), llr_not_sensitive),
        ("30-minute nights, no detection: too-sensitive side", lambda: (False, 0.5), llr_too_sensitive),
        ("detection 5 minutes in, each night: not-sensitive side", lambda: (True, 5/60), llr_not_sensitive),
        ("detection 1 minute in, each night: too-sensitive side", lambda: (True, 1/60), llr_too_sensitive),
        ("detection 30 seconds in, each night: too-sensitive side", lambda: (True, 0.5/60), llr_too_sensitive),
        ("detection 10 minutes in, each night: too-sensitive side", lambda: (True, 10/60), llr_too_sensitive),
        ("90-minute nights, no detection: not-sensitive side", lambda: (False, 1.5), llr_not_sensitive),
        ("10-minute nights, no detection: not-sensitive side", lambda: (False, 10/60), llr_not_sensitive),
    ]
    for name, fn, test in cases:
        n, verdict, s = nights_until(fn, test)
        print(f"  {name:58s} → {verdict} after {n} nights (sum {s:.4f})")
    print(f"  one night's evidence: sound at 5 min → too-sensitive {llr_too_sensitive((True, 5/60)):.4f}, "
          f"not-sensitive {llr_not_sensitive((True, 5/60)):.4f}")

def operating_characteristics(reps=4000, seed=1815):
    rng = random.Random(seed)
    print(f"\nOPERATING CHARACTERISTICS — settling at one step ({reps} people each, seed {seed})")
    windows = {"30 minutes": lambda r: 30, "changes nightly, 10–90": lambda r: r.choice((10, 20, 30, 45, 60, 90))}
    people = [("misses you 0.3/hr", 0.3), ("older adult 2.1/hr", 2.1), ("young adult 3.6/hr", 3.6),
              ("median mover 11/hr", 11.0), ("top of normal 18/hr", 18.0), ("restless 25/hr", 25.0),
              ("noisy room 54/hr", 54.0), ("noisy room 90/hr", 90.0)]
    for wname, wfn in windows.items():
        print(f"  window: {wname}")
        for name, rate in people:
            tally, lengths = {}, []
            for _ in range(reps):
                state, history = fresh_state(), []
                for n in range(CALIBRATION_NIGHT_CAP + 1):
                    history.append((n, state["step"], evidence(simulated_night(rate, wfn(rng), rng))))
                    state, action = evaluate(state, history, n)
                    if action != "none":
                        break
                tally[action] = tally.get(action, 0) + 1
                lengths.append(n + 1)
            lengths.sort()
            out = ", ".join(f"{k} {round(100*v/reps)}%" for k, v in sorted(tally.items(), key=lambda kv: -kv[1]))
            print(f"    {name:22s} {out:36s} median {lengths[len(lengths)//2]:2d} nights, 90% within {lengths[int(.9*len(lengths))]:2d}")

def ladder_scenarios(reps=2000, seed=7, nights=120):
    rng = random.Random(seed)
    print(f"\nLADDER — whole behaviour over {nights} nights ({reps} people each, start at medium)")
    scenarios = [
        ("medium already fits (4/hr at medium, doubling per step)", [1, 2, 4, 8, 16, 32], False),
        ("medium misses you (0.2/hr at medium)",                    [0.05, 0.1, 0.2, 0.4, 0.8, 1.6], False),
        ("owner-like: only the top steps hear you",                 [0.05, 0.1, 0.2, 0.3, 1.5, 4], False),
        ("noisy room, answers yes",                                 [10, 20, 40, 80, 160, 320], True),
        ("restless sleeper, answers no",                            [15, 30, 60, 120, 240, 480], False),
        ("cliff: misses below, noise above — loop guard",           [0.1, 0.2, 0.3, 100, 200, 400], True),
        ("never hears you at any step",                             [0.02, 0.03, 0.05, 0.08, 0.1, 0.15], False),
    ]
    for name, rates, yes in scenarios:
        finals, asks, stepups = {}, [], []
        for _ in range(reps):
            state, asked, steps = run_person(rates, yes, rng, nights)
            finals[state["step"]] = finals.get(state["step"], 0) + 1
            asks.append(asked); stepups.append(steps)
        asks.sort(); stepups.sort()
        dist = ", ".join(f"step {k} {round(100*v/reps)}%" for k, v in sorted(finals.items()))
        print(f"  {name}")
        print(f"    ends at: {dist}")
        print(f"    questions asked: median {asks[reps//2]}, max {asks[-1]};  step-ups: median {stepups[reps//2]}, max {stepups[-1]}")

def watching(seed=11, runs=300, cap=3000):
    rng = random.Random(seed)
    print("\nSETTLED — silence after settling (window changes nightly 10–90)")
    def run_length(rate, llr_fn, h):
        s = 0.0
        for n in range(1, cap + 1):
            night = simulated_night(rate, rng.choice((10, 20, 30, 45, 60, 90)), rng)
            s = max(0.0, s + llr_fn(evidence(night)))
            if s >= h: return n
        return cap
    for side, fn, h, bound, typical, shifted in (
        ("too sensitive → asks", llr_too_sensitive, WATCH_H_TOO_SENSITIVE, OK_HIGH, 11.0, TOO_HIGH),
        ("not sensitive → steps up", llr_not_sensitive, WATCH_H_NOT_SENSITIVE, OK_LOW, 3.6, TOO_LOW)):
        b = sorted(run_length(bound, fn, h) for _ in range(runs))
        t = sorted(run_length(typical, fn, h) for _ in range(runs))
        c = sorted(run_length(shifted, fn, h) for _ in range(runs))
        print(f"  {side} (h = {h}): sitting on the bound, median {b[runs//2]} nights before an unneeded action; "
              f"typical sleeper {'never in ' + str(cap) if t[runs//2] >= cap else 'median ' + str(t[runs//2])}; "
              f"a real change caught in median {c[runs//2]}, 90% within {c[int(.9*runs)]}")

if __name__ == "__main__":
    worked_examples()
    operating_characteristics()
    ladder_scenarios()
    watching()
