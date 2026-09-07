"""Grader-owned assertions against the student's own FastAPI app.

Run inside the fastapi container (never on the host) via check.sh:
    docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/<scenario> \\
        fastapi uv run python /grading/assert_aqi.py <scenario>

This imports the student's `main:app` directly and drives it with
fastapi.testclient.TestClient -- no server process, no port to manage, and
each scenario runs in a throwaway container so AQI_BASE_URL can differ per
call without restarting anything. It is the independent half of the
anti-fake design: the student's own pytest suite (run separately by
check.sh) must reach the same conclusions this script does, or the student
gains nothing by writing `assert True` three times.

Expected values for normal/boundary are derived from grading/fixtures/*.json
at run time (never hardcoded here) -- editing the fixture cannot silently
drift out of sync with what gets graded.

The error contract this file grades against (binding, restated in
NOTES.md / README.md):
  - happy path                       -> 200, exact current + next_hr dicts
  - current hour is hourly.time[-1]  -> 200, current exact, next_hr is null
  - upstream values are null         -> 200, nulls passed straight through
  - anything else goes wrong         -> 502, JSON body with an "error" key
    (current.time not in hourly.time; upstream non-200; body not JSON)

Exits 0 with an "OK ..." line on pass, exits 1 with a "FAIL ..." reason
on failure.
"""
import json
import sys

sys.path.insert(0, "/app")

from fastapi.testclient import TestClient  # noqa: E402

try:
    from main import app
except Exception as exc:  # student code missing/broken -- expected pre-Section-3
    print(f"FAIL import: {exc}")
    raise SystemExit(1)

client = TestClient(app)

REQUIRED_KEYS = {"AQI_US", "PM10", "PM2.5", "Time"}
FIXTURES = "/grading/fixtures"


def fail(msg):
    print(f"FAIL {msg}")
    raise SystemExit(1)


def ok(msg="ok"):
    print(f"OK {msg}")
    raise SystemExit(0)


def load_fixture(name):
    with open(f"{FIXTURES}/{name}.json", encoding="utf-8") as handle:
        return json.load(handle)


def expected_block(fixture, index):
    hourly = fixture["hourly"]
    return {
        "AQI_US": hourly["us_aqi"][index],
        "PM10": hourly["pm10"][index],
        "PM2.5": hourly["pm2_5"][index],
        "Time": hourly["time"][index],
    }


def check_shape(block, label):
    if not isinstance(block, dict):
        fail(f"{label} is not a JSON object")
    if set(block) != REQUIRED_KEYS:
        fail(f"{label} must have exactly the keys {sorted(REQUIRED_KEYS)}; got {sorted(block)}")


def scenario_normal():
    fixture = load_fixture("normal")
    idx = fixture["hourly"]["time"].index(fixture["current"]["time"])
    expected_current = expected_block(fixture, idx)
    expected_next = expected_block(fixture, idx + 1)

    resp = client.get("/api/aqi")
    if resp.status_code != 200:
        fail(f"GET /api/aqi returned {resp.status_code}, expected 200")
    data = resp.json()
    if set(data) != {"current", "next_hr"}:
        fail(f"/api/aqi must return exactly current and next_hr; got {sorted(data)}")
    check_shape(data["current"], "current")
    check_shape(data["next_hr"], "next_hr")
    if data["current"] != expected_current:
        fail(f"current mismatch: expected {expected_current}, got {data['current']}")
    if data["next_hr"] != expected_next:
        fail(f"next_hr mismatch: expected {expected_next}, got {data['next_hr']}")
    ok("normal: all eight values match grading/fixtures/normal.json")


def scenario_boundary():
    # current hour IS the last hourly.time entry, so `current` is still
    # exactly determined by the fixture -- but there is no real "next hour"
    # in the upstream data, so the binding contract is next_hr: null, status
    # 200. A naive `hourly.time.index(t) + 1` raises IndexError here
    # (uncaught -> bare 500 -> FAIL); the contract distinguishes that from a
    # bounded implementation that returns null on purpose.
    fixture = load_fixture("boundary")
    idx = fixture["hourly"]["time"].index(fixture["current"]["time"])
    if idx != len(fixture["hourly"]["time"]) - 1:
        fail("boundary fixture is broken: current.time is not the last hourly.time entry")
    expected_current = expected_block(fixture, idx)

    resp = client.get("/api/aqi")
    if resp.status_code != 200:
        fail(f"GET /api/aqi returned {resp.status_code}, expected 200 with next_hr: null")
    data = resp.json()
    if set(data) != {"current", "next_hr"}:
        fail(f"/api/aqi must return exactly current and next_hr; got {sorted(data)}")
    check_shape(data["current"], "current")
    if data["current"] != expected_current:
        fail(f"current mismatch: expected {expected_current}, got {data['current']}")
    if data["next_hr"] is not None:
        fail(f"next_hr must be JSON null when there is no next hour; got {data['next_hr']!r}")
    ok("boundary: current exact, next_hr is null")


def scenario_nulls():
    # Some upstream us_aqi/pm2_5 values are null. Contract: 200, normal
    # shape, nulls passed straight through (not coerced, not crashed on).
    resp = client.get("/api/aqi")
    if resp.status_code != 200:
        fail(f"nulls: GET /api/aqi returned {resp.status_code}, expected 200")
    data = resp.json()
    if set(data) != {"current", "next_hr"}:
        fail(f"nulls: /api/aqi must return exactly current and next_hr; got {sorted(data)}")
    check_shape(data["current"], "current")
    check_shape(data["next_hr"], "next_hr")
    # Compare exact values, not just shape. Shape-only let `(h["us_aqi"][n] or 0)`
    # through -- nulls silently coerced to 0 while the grader reported
    # "null values passed through". nulls.json holds one null in pm2_5 at the
    # current hour and one in us_aqi at the next, so this is a cheap exact test.
    fixture = load_fixture("nulls")
    idx = fixture["hourly"]["time"].index(fixture["current"]["time"])
    for label, want in (("current", expected_block(fixture, idx)),
                        ("next_hr", expected_block(fixture, idx + 1))):
        if data[label] != want:
            fail(
                f"nulls: {label} must pass the upstream values through unchanged, "
                f"null included; expected {want}, got {data[label]}"
            )
    ok("nulls: 200, shape intact, null values passed through unchanged")


def scenario_clean_502(name):
    # not_in_list / upstream_down / malformed: current.time missing from
    # hourly.time, upstream non-200, or a non-JSON body. Contract: 502 with
    # a JSON body carrying an "error" key. Never a bare 500 or a traceback.
    resp = client.get("/api/aqi")
    if resp.status_code != 502:
        fail(f"{name}: expected 502, got {resp.status_code}")
    try:
        data = resp.json()
    except ValueError:
        fail(f"{name}: 502 response body is not valid JSON")
    if "traceback" in resp.text.lower():
        fail(f"{name}: /api/aqi leaked a traceback")
    if not isinstance(data, dict) or "error" not in data:
        fail(f"{name}: 502 body must be a JSON object with an 'error' key; got {data!r}")
    ok(f"{name}: 502 with a clean error body")


def scenario_hourly():
    # Bonus B7: GET /api/hourly returns >= 12 hourly readings forward from
    # the current hour, each with the same four keys as current/next_hr.
    #
    # Values and ORDER are asserted against the fixture, not just shape. The
    # earlier shape-only version passed for 12 fabricated rows, rows in the
    # wrong order, or the entire hourly array dumped verbatim — a check that
    # passes for the wrong reason teaches nothing.
    resp = client.get("/api/hourly")
    if resp.status_code != 200:
        fail(f"hourly: GET /api/hourly returned {resp.status_code}, expected 200")
    data = resp.json()
    if not isinstance(data, list) or len(data) < 12:
        got = len(data) if isinstance(data, list) else type(data).__name__
        fail(f"hourly: expected a JSON list of at least 12 entries; got {got}")
    for i, row in enumerate(data):
        if not isinstance(row, dict) or set(row) != REQUIRED_KEYS:
            fail(f"hourly: entry {i} must have exactly the keys {sorted(REQUIRED_KEYS)}; got {row}")

    fixture = load_fixture("normal")
    times = fixture["hourly"]["time"]
    start = times.index(fixture["current"]["time"])
    if start + 12 > len(times):
        fail("normal fixture is broken: fewer than 12 hourly readings from the current hour")
    expected = [expected_block(fixture, i) for i in range(start, start + 12)]
    for i, (got_row, want_row) in enumerate(zip(data[:12], expected)):
        if got_row != want_row:
            fail(
                f"hourly: entry {i} must be the reading for {want_row['Time']} "
                f"(the {i}th hour from the current one); expected {want_row}, got {got_row}"
            )
    ok(f"hourly: {len(data)} entries, first 12 match the fixture exactly from {expected[0]['Time']}")


SCENARIOS = {
    "normal": scenario_normal,
    "boundary": scenario_boundary,
    "nulls": scenario_nulls,
    "not_in_list": lambda: scenario_clean_502("not_in_list"),
    "upstream_down": lambda: scenario_clean_502("upstream_down"),
    "malformed": lambda: scenario_clean_502("malformed"),
    "hourly": scenario_hourly,
}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in SCENARIOS:
        print(f"usage: assert_aqi.py <{'|'.join(SCENARIOS)}>")
        raise SystemExit(2)
    SCENARIOS[sys.argv[1]]()
