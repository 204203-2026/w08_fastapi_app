"""One-time generator: derive grading fixtures from the real captured
Open-Meteo response (normal.json). Deterministic — run once, commit outputs.
Kept in the repo (grading/generate_fixtures.py) for documentation/reproducibility;
not invoked by init.sh or check.sh.
"""
import copy
import json
from pathlib import Path

FIXDIR = Path(__file__).resolve().parent / "grading" / "fixtures"
if not FIXDIR.exists():
    FIXDIR = Path("grading/fixtures")

normal = json.loads((FIXDIR / "normal.json").read_text())

# --- boundary: current hour is the LAST entry in hourly.time ---
boundary = copy.deepcopy(normal)
boundary["current"] = {
    "time": normal["hourly"]["time"][-1],
    "interval": 3600,
    "us_aqi": normal["hourly"]["us_aqi"][-1],
    "pm10": normal["hourly"]["pm10"][-1],
    "pm2_5": normal["hourly"]["pm2_5"][-1],
}
(FIXDIR / "boundary.json").write_text(json.dumps(boundary))

# --- nulls: some us_aqi / pm2_5 entries are null near the current hour ---
nulls = copy.deepcopy(normal)
idx = normal["hourly"]["time"].index(normal["current"]["time"])
nulls["hourly"]["pm2_5"][idx] = None      # current hour's PM2.5 -> null
nulls["hourly"]["us_aqi"][idx + 1] = None  # next hour's AQI_US -> null
(FIXDIR / "nulls.json").write_text(json.dumps(nulls))

# --- not_in_list: current.time does not appear in hourly.time at all ---
not_in_list = copy.deepcopy(normal)
not_in_list["current"] = dict(normal["current"])
not_in_list["current"]["time"] = "2025-12-05T18:30"  # half-hour: not in hourly.time
(FIXDIR / "not_in_list.json").write_text(json.dumps(not_in_list))

# --- malformed: truncated / non-JSON body ---
raw = (FIXDIR / "normal.json").read_text()
(FIXDIR / "malformed.json").write_text(raw[: len(raw) // 3])

print("wrote:", sorted(p.name for p in FIXDIR.glob("*.json")))
