# Build Notes — w08_fastapi_app (AQI rework)

Rewrote the phonebook-era template to the AQI feature (Chiang Mai air
quality, swappable `AQI_BASE_URL`, an `aqi-fixture` compose service serving
designed payloads) per the "02 Slides" `CLAUDE.md` and a binding mid-task spec
update (ports, error contract, exact check list — see §"Binding spec update"
below). **Do not edit `README.md`** — a parallel agent owns the lab sheet;
this file is that agent's contract for what the code requires.

## What was built

- **Retired the phonebook.** `/api/me` is the new deterministic anchor
  (`{"name", "student_id"}`); `/api/aqi` fetches Open-Meteo and reshapes to
  `{"current": {...}, "next_hr": {...}}` with keys `AQI_US`, `PM10`,
  `"PM2.5"`, `Time`. `GET /` stays as a plain greeting — it's the
  `docker compose up` readiness-poll target, not content-graded.
- **`AQI_BASE_URL`** is `os.getenv("AQI_BASE_URL", "https://air-quality-api.open-meteo.com")`,
  read *inside* the request handler (not at import time), which is what lets
  the grader/tests swap it. Shipped `.env.example`; `.env` is gitignored;
  `docker-compose.yml` passes it through to the `fastapi` service.
- **`aqi-fixture`** — third compose service, `nginx:alpine`, serving
  `grading/fixtures/*.json` via `grading/nginx/default.conf`. Routing rule:
  `/<scenario>/<anything>?<any query>` → `<scenario>.json`, ignoring the
  query string entirely; `/upstream_down/...` → bare `503`. Verified with
  `curl`, including a double-slash path (see below).
- **Fixture scenarios**, all derived from the real captured Open-Meteo
  response (`~/git_projects/25S2_204212_submissions/204212_HW01_SHOT/API/data.json`,
  copied verbatim as `normal.json`) by `grading/generate_fixtures.py`
  (deterministic, committed, re-runnable — `python3 grading/generate_fixtures.py`
  reproduces the other four files byte-for-byte):
  - `normal.json` — verbatim capture. `current.time` = `hourly.time[18]` of 120.
  - `boundary.json` — `current` moved to the **last** `hourly.time` entry (index 119).
  - `nulls.json` — `hourly.pm2_5[18] = null`, `hourly.us_aqi[19] = null`.
  - `not_in_list.json` — `current.time` set to `"2025-12-05T18:30"` (a
    half-hour value that is not in `hourly.time`).
  - `malformed.json` — `normal.json` truncated to 1/3 length (invalid JSON).
- **The `/api/aqi` error contract** (binding, restated in README too):
  - happy path → 200, exact `current` + `next_hr` dicts.
  - current hour is `hourly.time[-1]` → 200, `current` exact, **`next_hr` is
    JSON `null`** (not `{}`, not a copy of `current`).
  - upstream values are `null` → 200, passed straight through.
  - anything else (time not found, upstream non-200, non-JSON body) → **502**
    with `{"error": "<reason>"}`, never a bare 500 / traceback.
- **`/api/hourly`** (bonus B7): `>= 12` readings forward from the current
  hour, same 4 keys each; `App.vue` renders them in a `<table>`.
- **`grading/assert_aqi.py`** — the grader's own assertions, run via
  `docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/<scenario>
  fastapi uv run python /grading/assert_aqi.py <scenario>`. Uses
  `fastapi.testclient.TestClient` against the student's own `main:app` — no
  server process, no port, and each scenario is an isolated one-off
  container so `AQI_BASE_URL` never has to change on the long-running
  service. **Expected values for `normal`/`boundary` are derived from
  `grading/fixtures/*.json` at run time** (never hardcoded) — editing a
  fixture cannot silently drift out of sync with what's graded.
- **`check.sh`** reworked: 10 required checks, 7 bonus checks (see below).
  `record`/`record_bonus`, no `set -e`, `x=$((x+1))`, always `exit 0`,
  `ROOT=$(git rev-parse --show-toplevel ...)`, `trap` on `docker compose
  down -v --remove-orphans` all preserved. **Anti-fake property preserved**:
  `tests_pass` runs the student's own pytest suite; `me_endpoint`,
  `aqi_normal`, `aqi_boundary` run the grader's *own* HTTP/TestClient
  assertions against the live app — a student writing `assert True` three
  times still fails those three checks (see the comment block above R5 in
  `check.sh`).
- **`DEPLOY_URL.txt` → `vercel_url.txt`** everywhere (`check.sh`,
  `submit.sh`). Parsing: strip whitespace + trailing slash, skip blanks/`#`
  comments, first `https://`-prefixed line. Missing/unreachable → `TODO`,
  never `FAIL`. The resolved URL is echoed into
  `results/challenge_report.json` as a `"url"` field on the `deployed`
  entry. **`.gitignore` no longer ignores this filename** (the old
  `.gitignore` ignored `DEPLOY_URL.txt`, which meant `git add` would have
  silently refused it — a real bug, now fixed by removing the line, not
  replacing it).
- **`.dockerignore` files graded**: `fastapi/.dockerignore` and
  `frontend/.dockerignore` added to the `structure` check's required-files
  list (previously taught, never graded).
- **Placeholder heuristic adopted from `check_api_data.py`** (204212 HW01):
  reject a `name` value containing `<` and `>`, or the words `your`, `name`,
  `phone`, `somchai` (case-insensitive) — plus `student_id` must match
  `^[0-9]{9}$`.
- **`fastapi/pyproject.toml` gained `[tool.pytest.ini_options]
  pythonpath = ["."]`** — see "Important finding" below; without it the TDD
  red step breaks in a way the lab sheet must not let students hit silently.

## Binding spec update (mid-task)

A parallel README-planning agent's plan landed mid-build and pinned down
several contracts more precisely than the original brief; it explicitly said
"this plan wins" for ports, the `/api/aqi` error contract, and the check
list. Adopted in full:

- **Ports changed**: fastapi host port `8000` → **`56733`**; aqi-fixture
  host port → **`8001`** (was `8090` in my first draft). Frontend stays
  `8080`. The **internal** compose network is unchanged — `fastapi:8000` is
  still the Vite proxy target and the DNS name `aqi-fixture` (container port
  `80`) is still what `AQI_BASE_URL` points student code at. All host-side
  `curl`/readiness-poll URLs in `check.sh` were updated to `56733`.
- **`/api/aqi` error contract tightened**: `next_hr` must be exactly JSON
  `null` on the boundary scenario (not shape-only, no clamping) and
  `not_in_list`/`upstream_down`/`malformed` must be exactly `502` with an
  `"error"` key (not merely "not a 500"). My first draft (written before this
  update, and preserved in the earlier commit history / conversation) used
  softer contracts (shape-only boundary, "not 500" for bonus scenarios); this
  version supersedes it everywhere — code, fixtures, and `assert_aqi.py`.
- **`/api/me`** gained the `student_id` format requirement (`^[0-9]{9}$`) and
  the `somchai` placeholder word (carried over from the old
  `ROOT_REJECTION` string in the pre-AQI `check.sh`).
- **Check list is exactly 10 required + 7 bonus** (see below) — I did *not*
  adopt the same plan's `docker/` staging-directory restructuring (moving
  `fastapi/Dockerfile` etc. into a top-level `docker/` folder that students
  `cp` into place) because the coordinator's instruction explicitly scoped
  the override to "§2 Check list, §2 error contract, and the Ports table" —
  not the rest of that plan's "Template ships" section. `fastapi/Dockerfile`,
  `fastapi/.dockerignore`, `frontend/Dockerfile`, `frontend/.dockerignore`
  remain pre-shipped in `fastapi/`/`frontend/` as they were before this
  task, unchanged in that respect. **Flagging this explicitly**: if the
  README is written assuming a `docker/` staging directory and `cp` steps,
  it will not match the shipped repo — the repo has these files already in
  place under `fastapi/` and `frontend/`.

## Required checks (10) — `check.sh`

| check | what it verifies |
|---|---|
| `structure` | all required files exist, incl. both `.dockerignore`s, `docker-compose.yml`, `.env.example` |
| `uv_deps` | `fastapi`, `uvicorn`, `httpx` in `dependencies`; `pytest` in the dev group; non-empty `uv.lock` |
| `compose_up` | `docker compose up -d --build` serves `GET /` → 200 on port `56733` |
| `me_endpoint` | `GET :56733/api/me` → 200, `{"name","student_id"}`, placeholder heuristic, `student_id` is 9 digits |
| `tests_pass` | student's own `pytest -q` (env: `AQI_BASE_URL=http://aqi-fixture/normal`) exits 0 **and** reports `>= 3 passed` |
| `aqi_normal` | grader's own assertion: all 8 values exact vs. `grading/fixtures/normal.json`, derived at run time |
| `aqi_boundary` | grader's own assertion: `current` exact, `next_hr` is JSON `null` |
| `vue_static` | `frontend/package.json` has `vue` + `@vitejs/plugin-vue`; no `jquery`; `App.vue` has `v-for`, `{{`, and `/api/aqi` (either quote style) |
| `proxy_config` | `vite.config.js` has `proxy`, `'/api'`, `http://fastapi:8000`, `0.0.0.0` |
| `proxy_live` | `GET :8080/api/me` (through the Vite proxy) equals `GET :56733/api/me` (direct) |

## Bonus checks (7) — `results/challenge_report.json`

| check | contract |
|---|---|
| `frontend_build` | `npm ci && npm run build` produces `frontend/dist/index.html` |
| `deployed` | `vercel_url.txt` → `GET <url>/api/me` returns a JSON object; URL echoed as `"url"` field |
| `aqi_nulls` | `nulls` scenario → 200, shape intact, nulls passed through |
| `aqi_not_in_list` | `not_in_list` scenario → 502 + `{"error": ...}` |
| `aqi_upstream_down` | `upstream_down` scenario → 502 + `{"error": ...}` |
| `aqi_malformed` | `malformed` scenario → 502 + `{"error": ...}` |
| `hourly_table` | `GET /api/hourly` returns `>= 12` dicts with the 4 AQI keys, **and** `App.vue` contains `<table` |

## Verification (all run live in this environment)

### 1. Reference solution — scratch copy `/tmp/w08_ref`

Built a full working solution: `uv init --bare --name backend .` in
`fastapi/` (then `uv add fastapi uvicorn httpx` + `uv add --dev pytest`),
`npm create vite@latest -- --template vue` scaffolded into `frontend/`
(merged with the existing Dockerfile/`.dockerignore`), full `main.py`
(`/`, `/api/me`, `/api/aqi`, `/api/hourly`), 3 pytest tests, `vite.config.js`
with the required proxy object, `App.vue` rendering `current`/`next_hr` plus
an hourly `<table>`.

```
bash init.sh   # all 6 tool checks green
bash check.sh  # RESULT:
```

```
Score: 10 / 10 required   |   0 failed
Bonus: 5 / 7 challenges
```

(The 2 bonus misses are expected and correct: `frontend_build` needs a root
`package-lock.json` I didn't generate via `npm install`/`npm ci` in this
scratch run, and `deployed` needs a real `vercel_url.txt` — neither is part
of "full marks on the required checks.")

### 2. Shipped (unmodified) template — scratch copy `/tmp/w08_template`

```
bash check.sh   # exit code: 0
```

```
Score: 1 / 10 required   |   9 failed
Bonus: 0 / 7 challenges
```

Only `structure` passes (all starter files exist). `uv_deps` correctly
fails because the starter `uv.lock` is a text marker, not a real lock file
— and (important finding, see below) the starter `pyproject.toml`'s
`dependencies = []` means `docker compose build` fails at
`uv sync --frozen` (invalid lock), so `compose_up` and everything
downstream fails cleanly, not crashes. No exception, no hang, exit 0.
**This exact run's `results/report.json` and `results/challenge_report.json`
are what's committed** (per review: commit the template's real run, not the
reference solution's).

### 3. Two consecutive `check.sh` runs — leak check

Ran `bash check.sh` twice back to back against the reference solution.
Both scored `10/10` (5/7 bonus) identically. After **each** run:

```
lsof -nP -iTCP:56733 -sTCP:LISTEN   # empty
lsof -nP -iTCP:8080  -sTCP:LISTEN   # empty
lsof -nP -iTCP:8001  -sTCP:LISTEN   # empty
lsof -nP -iTCP:8765  -sTCP:LISTEN   # empty (never used by this lab; checked anyway per instructions)
docker ps                            # empty (no containers)
```

Also ran the leak check after the shipped-template run (score 1/10) — same,
all empty. `pgrep -fl uvicorn` was **not** used for this (per the task's own
warning that it false-positives on this machine); `lsof` + `docker ps` were
used throughout.

### 4. Fixture routing proof

Brought up just `aqi-fixture` from the real repo's `docker-compose.yml`
(port `8001`) and curled it directly:

```
$ curl -s "http://127.0.0.1:8001/normal/v1/air-quality?foo=1" | head -c 150
{"latitude":18.800003,"longitude":98.899994, ... "timezone":"Asia/Bangkok", ...

$ curl -s "http://127.0.0.1:8001/normal//v1/air-quality?foo=1" | head -c 150   # double slash
{"latitude":18.800003,"longitude":98.899994, ... "timezone":"Asia/Bangkok", ...

$ curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:8001/upstream_down/v1/air-quality?x=1"
503
```

Both the normal path and a double-slash variant (what a trailing slash in
`.env`'s `AQI_BASE_URL` would produce) resolve to the same fixture file;
`upstream_down` returns a bare 503 regardless of path/query, as designed.

### 5. Boundary-bug proof

Added a deliberately naive `/api/aqi_naive` route
(`next_hr = _reshape(data, idx + 1)`, no bounds check) alongside the correct
`/api/aqi`, pointed `AQI_BASE_URL` at `http://aqi-fixture/boundary` (current
hour = last `hourly.time` entry), and called both via `TestClient` inside a
`docker compose run` container:

```
naive impl    -> 500 Internal Server Error
correct impl  -> 200 {"current":{"AQI_US":115,"PM10":51.6,"PM2.5":50.2,"Time":"2025-12-09T23:00"},"next_hr":null}
```

Confirmed `grading/assert_aqi.py`'s `boundary` scenario correctly treats the
naive implementation's `500` as a failure (`resp.status_code != 200` in the
grader's flow) and the correct implementation's `next_hr: null` as a pass.

### 6. TDD red proof

With `main.py` reduced to only `/` and `/api/me` (no `/api/aqi`,
`/api/hourly`), ran the 3 reference tests in-container:

```
tests/test_api.py::test_me PASSED
tests/test_api.py::test_aqi_shape FAILED — assert 404 == 200
tests/test_api.py::test_aqi_next_hour_is_one_hour_after_current FAILED — assert 404 == 200
2 failed, 1 passed
```

Clean assertion failures on the response status, not a collection or import
error — exactly what the TDD-red step needs (each test's first assertion is
`resp.status_code == 200` before touching the body, per review guidance).
Restoring the full `main.py` turned all 3 green again (`3 passed`).

### 7. Static checks

- `bash -n init.sh check.sh submit.sh` — all pass, no syntax errors.
- `python3 -c "import json; json.load(...)"` on both `results/*.json` files
  (both the reference-run and the final committed template-run versions) —
  valid.
- `python3 grading/generate_fixtures.py` re-run from the repo root — regenerates
  all 4 derived fixtures byte-identical to the committed copies (`git status`
  clean after).

## Important finding for the README author (not just a nice-to-have)

**`pytest` cannot import `main` from `tests/test_api.py` without
`pythonpath = ["."]` in `[tool.pytest.ini_options]`.** Discovered empirically:
pytest's default "prepend" import mode only puts `tests/` on `sys.path`
(since there's no `__init__.py` there), not the `/app` root where `main.py`
lives — so `from main import app` raises `ModuleNotFoundError`, and pytest
reports it as a **collection error**, not a failing assertion. This breaks
the "TDD red must fail for the right reason" requirement (task step 6 /
CLAUDE.md's "Simple TDD" section) — a student who reaches Section 3's first
`pytest` run without this line gets a confusing collection error instead of
the clean `assert 404 == 200` the lesson depends on.

**Fix applied**: added
```toml
[tool.pytest.ini_options]
pythonpath = ["."]
```
to the shipped `fastapi/pyproject.toml` stub (confirmed empirically that
`uv add` preserves this section when it later rewrites `dependencies = []`).
**The README must NOT tell students to add this line themselves as a new
step** — it should already be present when they open `fastapi/pyproject.toml`
in Section 1, and the sheet can just point it out in passing (one line,
alongside the `dependency-groups` gloss) rather than as a "type this" step.
If the README is drafted from a plan that assumes a bare `uv init --bare`
scaffold with no pre-existing `pyproject.toml`, tell it to add this exact
block right after scaffolding, before the first pytest run in Section 3.

## Known limitation — please state honestly, don't oversell "no network"

**`docker compose run --rm fastapi uv run pytest -q` needs network access**
the first time it runs, because the `fastapi` image is built with
`uv sync --frozen --no-dev --no-install-project` (per CLAUDE.md's Docker
section) — dev dependencies (`pytest`, and anything else in the dev group)
are deliberately **not** baked into the image. When `uv run pytest` executes
inside the container, `uv` auto-syncs the dev group on demand, which needs
to fetch wheels from PyPI unless they're already in `uv`'s cache. Verified
directly:

```
$ docker compose run --rm -T -e AQI_BASE_URL=... -e UV_OFFLINE=1 fastapi uv run pytest -q
× Failed to download `pygments==2.21.0`
  Network connectivity is disabled, but the requested data wasn't found in
  the cache for: https://files.pythonhosted.org/packages/.../pygments-...whl
```

Without `UV_OFFLINE=1` (i.e. with network available, the normal case on a
student's machine and on `ubuntu-latest` CI runners) it works fine and
finishes in well under a second after the one-time download. **The "no
network at all" property in CLAUDE.md refers specifically to the Open-Meteo
dependency being replaced by `aqi-fixture`** — not to a total network-free
grading environment. I did not change the Dockerfile's `--no-dev` (that's
prescribed by CLAUDE.md, not something to "fix" here); flagging it instead,
per review guidance. The README should not claim `check.sh`/CI need zero
network — only that the AQI upstream is never touched.

## What I could NOT verify

- **A live Vercel deployment.** `vercel_url.txt` and the `deployed` bonus
  check were exercised only with the file absent (correctly `TODO`); I did
  not deploy anything to Vercel to test the reachable-URL path end-to-end.
  The URL-parsing logic (forgiving parse, `TODO` on unreachable, `"url"`
  field echoed into `challenge_report.json`) was verified structurally and
  against a missing file, not against a real deployment.
- **`npm run build` bonus (`frontend_build`) against the real Vite scaffold**
  in the committed repo — I verified the Vite+Vue scaffold's *content*
  (package.json, vite.config.js, App.vue) is correct and that `npm create
  vite` produces a working dev server, but did not run a full `npm ci &&
  npm run build` from the repo root against the exact committed
  `frontend/package.json` (only against my scratch reference's merged
  scaffold, without generating a root `package-lock.json`, so that specific
  bonus check reported `TODO` in the reference run rather than `DONE` — this
  is expected, not a defect, but I want to be explicit that the *build
  itself* wasn't independently re-verified from a clean `git clone` of the
  final committed tree).
- CI (`.github/workflows/verify.yml` / `challenge.yml`) itself was not run
  through actual GitHub Actions — only inspected. It calls `init.sh` then
  `check.sh` exactly as done here, so the local runs above are believed
  representative, but GitHub's `ubuntu-latest` environment was not literally
  exercised.

## What README.md must tell students (precise list for the parallel agent)

**Commands, in the order a student runs them:**
1. `bash init.sh` — checks git/uv/node/npm/docker, exits 1 with per-tool
   fix instructions if anything's missing, exits 0 with "Open README.md and
   begin Section 1" when ready.
2. In `fastapi/`: `uv add fastapi uvicorn httpx` (all three as **runtime**
   dependencies — `httpx` is not dev-only, it's what `/api/aqi` uses to call
   Open-Meteo), then `uv add --dev pytest` (httpx is already a runtime dep,
   so it does not need to be re-added under `--dev` for `TestClient` to
   work). The shipped `fastapi/uv.lock` is a placeholder text marker —
   students must let `uv add` regenerate it (do not manually edit or
   preserve the placeholder content).
3. In `frontend/`: `npm create vite@latest . -- --template vue` (or
   `npm create vite@latest frontend -- --template vue` from the repo root,
   then merge) — the shipped `frontend/package.json`, `index.html`,
   `src/main.js` are throwaway placeholders meant to be replaced by the
   real Vite scaffold's versions of those same files. Keep the existing
   `frontend/Dockerfile` and `frontend/.dockerignore` — they are NOT part of
   the Vite scaffold and already ship correctly.
4. `docker compose up -d --build` (all three services: `fastapi`,
   `frontend`, `aqi-fixture`) — this is the **only** way to run the app;
   nothing runs bare-metal.
5. `docker compose run --rm fastapi uv run pytest -q` — how to run the
   student's own test suite (matches what `check.sh`'s `tests_pass` runs,
   with `AQI_BASE_URL` forced to `http://aqi-fixture/normal` there).
6. `bash check.sh` then `bash submit.sh`.

**Exact filenames/paths that matter:**
- `fastapi/main.py` — must define `app = FastAPI()`, `GET /`, `GET /api/me`,
  `GET /api/aqi` (and, for the bonus, `GET /api/hourly`).
- `fastapi/tests/test_api.py` — at least 3 `test_`-prefixed functions.
- `frontend/src/App.vue` — must fetch the **literal string** `/api/aqi`
  (single or double quotes both accepted by the grader), use `v-for` and
  `{{ }}` interpolation. For the `hourly_table` bonus, also needs a `<table`
  element.
- `frontend/vite.config.js` — must literally contain the substrings `proxy`,
  `/api` (quoted), `http://fastapi:8000`, and `0.0.0.0` (host binding). Full
  object shape:
  ```js
  server: {
    host: '0.0.0.0',
    port: 8080,
    proxy: { '/api': 'http://fastapi:8000' },
  }
  ```
- `.env.example` → copy to `.env` for local overrides (optional — the
  default already points at real Open-Meteo). `.env` is gitignored.
- `vercel_url.txt` — **repo root**, exact filename (not `DEPLOY_URL.txt` —
  that name is retired). One `https://` URL per line is fine; blank lines
  and `#` comments are skipped; trailing slash is stripped.

**Env vars:**
- `AQI_BASE_URL` — read inside the `/api/aqi` (and `/api/hourly`) handler,
  not at module import time. Default (unset) = real Open-Meteo
  (`https://air-quality-api.open-meteo.com`). Grading always overrides it to
  `http://aqi-fixture/<scenario>`.

**Ports (state exactly once, in a table):**

| port | reaches | notes |
|---|---|---|
| `56733` | `fastapi` container, host-side | e.g. `curl http://localhost:56733/api/me` |
| `8080` | `frontend` container, host-side | the page; `/api/*` is proxied to `fastapi:8000` internally |
| `8001` | `aqi-fixture` container, host-side | browse `http://localhost:8001/normal/v1/air-quality?...` etc. |
| `8000` | internal compose network only | uvicorn's real port; **do not** curl this from the host |

**The `/api/aqi` reshape contract (exact key spelling — the dot in `PM2.5`
is real, not a typo):**
```json
{
  "current":  {"AQI_US": <int>, "PM10": <float>, "PM2.5": <float>, "Time": "<iso8601>"},
  "next_hr":  {"AQI_US": <int>, "PM10": <float>, "PM2.5": <float>, "Time": "<iso8601>"}
}
```
Mapped from upstream's `hourly.us_aqi` / `hourly.pm10` / `hourly.pm2_5` /
`hourly.time`, at the index found via
`hourly.time.index(current.time)` and that index + 1.

**The error contract (state plainly, it's binding and graded):**
- current hour is the **last** entry in `hourly.time` → 200, `current`
  exact, `next_hr` is **JSON `null`** — not `{}`, not a copy of `current`.
- upstream values are `null` → 200, pass them straight through.
- anything else that goes wrong (current time not in `hourly.time`,
  upstream returns non-200, or the body isn't valid JSON) → **502** with
  `{"error": "<short reason>"}` — never a raw traceback, never a bare 500.
- "It worked against the real API" is not evidence it's correct — the
  grader feeds the endpoint fixture payloads specifically designed to break
  naive implementations (this sentence, or one very like it, should appear
  in the sheet per CLAUDE.md's course-thesis section).

**`/api/me` placeholder rule (state plainly):** the grader rejects a `name`
containing `<` and `>`, or the words `your`, `name`, `phone`, `somchai`
(case-insensitive) anywhere in the value — so partially-edited placeholders
still fail. `student_id` must be exactly 9 digits.

**Required vs. bonus, and pass/fail semantics:** 10 required checks must all
pass for full required marks; 7 bonus checks never affect the required
score. `bash check.sh` always exits 0 — pass/fail lives in
`results/report.json`/`results/challenge_report.json`, not the exit code.
Docker missing/not running is a **required FAIL**, not a TODO (Docker is
mandatory infrastructure for this lab, per CLAUDE.md).

**The `pytest` ini-options note** (see "Important finding" above) — worth
one sentence in Section 1 so students don't wonder why `pyproject.toml`
already has a `[tool.pytest.ini_options]` block they didn't type.
