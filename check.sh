#!/usr/bin/env bash
# Week 8 self-check. Required results and bonuses stay separate.
# No `set -e`: every failure becomes a useful report entry.
#
# Ports: 56733 -> fastapi container (was 8000 on the host; 8000 is still the
# port INSIDE the compose network and the Vite proxy target). 8080 -> the
# frontend container. 8001 -> aqi-fixture, browseable by students. Grading
# never touches the real Open-Meteo host: AQI_BASE_URL is pointed at the
# aqi-fixture compose service for every scenario below.

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 0

RESULTS="results"
JSON="$RESULTS/report.json"
CHALLENGE_JSON="$RESULTS/challenge_report.json"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
BONUS=0
BONUS_DONE=0
REQ_ITEMS=""
BONUS_ITEMS=""
DOCKER_READY=false
COMPOSE_TOUCHED=false
COMPOSE_READY=false
ME_DIRECT_OK=false
PROXY_OK=false

mkdir -p "$RESULTS"

record() {
  local name=$1 status=$2 msg=$3
  if [ "$status" = "PASS" ]; then
    echo -e "${GREEN}✅ $name PASS${NC} — $msg"
    PASS=$((PASS + 1))
    REQ_ITEMS="$REQ_ITEMS{\"name\": \"$name\", \"status\": \"pass\"},"
  else
    echo -e "${RED}❌ $name FAIL${NC} — $msg"
    FAIL=$((FAIL + 1))
    REQ_ITEMS="$REQ_ITEMS{\"name\": \"$name\", \"status\": \"fail\"},"
  fi
}

# record_bonus optionally takes an extra key=value pair (e.g. url=...) that
# gets echoed straight into that entry's challenge_report.json object, so
# live URLs (etc.) can be harvested in bulk across student repos.
record_bonus() {
  local name=$1 status=$2 msg=$3 extra_field=$4
  BONUS=$((BONUS + 1))
  if [ "$status" = "DONE" ]; then
    echo -e "${GREEN}⭐ $name BONUS${NC} — $msg"
    BONUS_DONE=$((BONUS_DONE + 1))
    BONUS_ITEMS="$BONUS_ITEMS{\"name\": \"$name\", \"status\": \"bonus\"${extra_field:+, $extra_field}},"
  else
    echo -e "${YELLOW}☆ $name (optional)${NC} — $msg"
    BONUS_ITEMS="$BONUS_ITEMS{\"name\": \"$name\", \"status\": \"todo\"${extra_field:+, $extra_field}},"
  fi
}

section() { echo ""; echo -e "${CYAN}── $1 ──${NC}"; }

run_python() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  else
    uv run --no-project python "$@"
  fi
}

run_bounded() {
  local seconds=$1
  shift
  run_python - "$seconds" "$@" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run(sys.argv[2:], timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    raise SystemExit(124)
raise SystemExit(result.returncode)
PY
}

cleanup_compose() {
  if $COMPOSE_TOUCHED; then
    run_bounded 120 docker compose down -v --remove-orphans >/dev/null 2>&1
    COMPOSE_TOUCHED=false
    COMPOSE_READY=false
  fi
}
trap cleanup_compose EXIT

echo "=============================================="
echo "  w08_fastapi_app — Self Check"
echo "=============================================="

if command -v docker >/dev/null 2>&1 \
  && docker compose version >/dev/null 2>&1 \
  && docker info >/dev/null 2>&1; then
  DOCKER_READY=true
fi

section "Required"

# R1 — files students create during Sections 1–8, plus the .dockerignore
# files taught but previously ungraded, plus the compose/env infrastructure.
required_files="
fastapi/main.py
fastapi/pyproject.toml
fastapi/uv.lock
fastapi/Dockerfile
fastapi/.dockerignore
fastapi/tests/test_api.py
frontend/index.html
frontend/package.json
frontend/vite.config.js
frontend/Dockerfile
frontend/.dockerignore
frontend/src/main.js
frontend/src/App.vue
docker-compose.yml
.env.example
"
missing=""
for path in $required_files; do
  [ -f "$path" ] || missing="${missing}${missing:+, }$path"
done
if [ -z "$missing" ]; then
  record "structure" "PASS" "all backend, frontend, test, Docker, compose, and env-example files exist"
else
  record "structure" "FAIL" "create these missing files: $missing"
fi

# R2 — uv declarations and lockfile. httpx is the runtime AQI client, so it
# is checked as a runtime dep; it may additionally sit in the dev group for
# TestClient (checked separately, not required twice).
uv_reason=$(run_python - <<'PY'
from pathlib import Path
import re

path = Path("fastapi/pyproject.toml")
lock = Path("fastapi/uv.lock")
if not path.is_file():
    print("create fastapi/pyproject.toml with uv init --bare --name backend fastapi")
    raise SystemExit(1)
try:
    text = path.read_text(encoding="utf-8").lower()
except OSError:
    print("make fastapi/pyproject.toml readable")
    raise SystemExit(1)
deps_match = re.search(r"dependencies\s*=\s*\[(.*?)\]", text, re.S)
dev_section = re.search(r"\[dependency-groups\](.*?)(?:\n\[|\Z)", text, re.S)
dev_match = re.search(r"dev\s*=\s*\[(.*?)\]", dev_section.group(1), re.S) if dev_section else None
deps = deps_match.group(1) if deps_match else ""
dev = dev_match.group(1) if dev_match else ""
missing = [name for name in ("fastapi", "uvicorn", "httpx") if name not in deps]
missing += [name for name in ("pytest",) if name not in dev]
if missing:
    print("add missing uv dependencies: " + ", ".join(missing))
    raise SystemExit(1)
if not lock.is_file() or lock.stat().st_size == 0:
    print("create a non-empty fastapi/uv.lock with uv add")
    raise SystemExit(1)
print("ok")
PY
)
if [ "$uv_reason" = "ok" ]; then
  record "uv_deps" "PASS" "fastapi, uvicorn, httpx and dev pytest are declared; uv.lock is non-empty"
else
  record "uv_deps" "FAIL" "$uv_reason"
fi

# Bring the whole stack up once, pointed at the aqi-fixture "normal" scenario.
# Every required/bonus check below reuses this single stack — no per-check
# restarts, and different AQI scenarios are exercised via one-off
# `docker compose run` containers (see grading/assert_aqi.py) so the live
# service's env never has to change mid-run.
if $DOCKER_READY; then
  COMPOSE_TOUCHED=true
  export AQI_BASE_URL="http://aqi-fixture/normal"
  run_bounded 420 docker compose up -d --build > /tmp/w08-compose-$$.log 2>&1
  compose_status=$?
  if [ "$compose_status" -eq 0 ]; then
    # Readiness is THREE separate facts, deliberately not one. The stack is up
    # as soon as GET / answers (end of Section 2). /api/me arrives in Section 3
    # and the Vite proxy only in Section 7, so folding them together would keep
    # compose_up red for six sections and blame Docker for unwritten code.
    attempt=0
    while [ "$attempt" -lt 60 ]; do
      root_ok=false
      curl --fail --silent --max-time 1 http://127.0.0.1:56733/ >/dev/null 2>&1 && root_ok=true
      if $root_ok; then
        COMPOSE_READY=true
        break
      fi
      sleep 1
      attempt=$((attempt + 1))
    done
    # Backend is listening; give the later-section endpoints a short grace
    # period. Their absence is a section not yet done, never a stack failure.
    if $COMPOSE_READY; then
      attempt=0
      while [ "$attempt" -lt 20 ]; do
        ME_DIRECT_OK=false
        PROXY_OK=false
        curl --fail --silent --max-time 1 http://127.0.0.1:56733/api/me > /tmp/w08-me-direct-$$.json 2>/dev/null && ME_DIRECT_OK=true
        # Must be JSON. With no `proxy` block at all, Vite's SPA fallback answers
        # /api/me with 200 + index.html, which a bare curl would accept as "the
        # proxy works".
        if curl --fail --silent --max-time 1 http://127.0.0.1:8080/api/me > /tmp/w08-me-proxy-$$.json 2>/dev/null \
          && run_python -c 'import json,sys; json.load(open(sys.argv[1]))' /tmp/w08-me-proxy-$$.json >/dev/null 2>&1; then
          PROXY_OK=true
        fi
        if $ME_DIRECT_OK && $PROXY_OK; then
          break
        fi
        sleep 1
        attempt=$((attempt + 1))
      done
    fi
  fi
fi

# R3 — the stack actually starts and serves. Content is graded separately
# (R4+) — this only proves docker compose up brings fastapi (and its
# aqi-fixture dependency) to a listening, HTTP-200 state.
if ! $DOCKER_READY; then
  record "compose_up" "FAIL" "start Docker Desktop / install Docker, then rerun bash check.sh"
elif $COMPOSE_READY; then
  record "compose_up" "PASS" "docker compose up -d --build serves GET / on port 56733"
else
  record "compose_up" "FAIL" "make docker compose up -d --build serve port 56733; inspect /tmp/w08-compose-$$.log"
fi

# R4 — grader-owned /api/me assertion: shape, a 9-digit student_id, and the
# placeholder heuristic adapted from 204212 HW01's check_api_data.py: rejects
# <...> and the shipped placeholder PHRASES ("replace me", "your name", ...),
# case-insensitively. It deliberately does NOT substring-match bare words —
# doing so rejected real Thai names on a required check.
if ! $COMPOSE_READY; then
  record "me_endpoint" "FAIL" "make docker compose up -d --build serve port 56733; inspect /tmp/w08-compose-$$.log"
elif ! $ME_DIRECT_OK; then
  record "me_endpoint" "FAIL" "add GET /api/me to fastapi/main.py — http://localhost:56733/api/me did not answer (Section 3)"
else
  me_reason=$(run_python - /tmp/w08-me-direct-$$.json <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError):
    print("return valid JSON from GET /api/me")
    raise SystemExit(1)
if not isinstance(data, dict) or "name" not in data or "student_id" not in data:
    print("return a JSON object with name and student_id from GET /api/me")
    raise SystemExit(1)


def is_placeholder(value):
    # Match the shipped placeholder PHRASES, never bare substrings. The old
    # version rejected any name containing "your", "name", "phone" or
    # "somchai", which fails real Thai names -- Somchai Jaidee, Anamet
    # Sae-Lim ("name"), Phonepaseuth Vong ("phone") -- on a REQUIRED check,
    # capping an honest student at 9/10 unless they falsify their own name.
    text = str(value)
    if "<" in text and ">" in text:
        return True
    low = " ".join(text.lower().split())
    if low in ("", "name", "phone", "your", "your name", "student", "student id"):
        return True
    return any(
        phrase in low
        for phrase in ("replace me", "replace this", "your name", "your phone", "your student")
    )


if is_placeholder(data["name"]):
    print("replace the placeholder name in GET /api/me with your own")
    raise SystemExit(1)
if not re.fullmatch(r"[0-9]{9}", str(data["student_id"])):
    print("student_id in GET /api/me must be exactly 9 digits")
    raise SystemExit(1)
print("ok")
PY
)
  if [ "$me_reason" = "ok" ]; then
    record "me_endpoint" "PASS" "GET /api/me returns your name and a 9-digit student ID"
  else
    record "me_endpoint" "FAIL" "$me_reason"
  fi
fi

# R5 — run the student's own pytest suite against the aqi-fixture "normal"
# scenario, inside the container, and require it to report >= 3 PASSING
# tests (not just exit 0 — a deleted test file also exits 0). This is one
# half of the anti-fake design: R6/R7/R10 below run the grader's OWN
# assertions against the live API, so a student who writes three
# `assert True` tests still fails those. Both must agree.
if ! $DOCKER_READY; then
  record "tests_pass" "FAIL" "start Docker Desktop / install Docker, then rerun bash check.sh"
else
  run_bounded 360 docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/normal fastapi uv run pytest -q > /tmp/w08-tests-$$.log 2>&1
  tests_status=$?
  passed_count=$(grep -Eo '[0-9]+ passed' /tmp/w08-tests-$$.log | tail -1 | grep -Eo '^[0-9]+')
  passed_count=${passed_count:-0}
  if [ "$tests_status" -eq 124 ]; then
    record "tests_pass" "FAIL" "container tests timed out; inspect docker compose logs fastapi"
  elif [ "$tests_status" -eq 0 ] && [ "$passed_count" -ge 3 ]; then
    record "tests_pass" "PASS" "student pytest suite passes ($passed_count passed) inside the fastapi container"
  else
    record "tests_pass" "FAIL" "define and pass at least 3 tests; found $passed_count passed. Run: docker compose run --rm fastapi uv run pytest -q"
  fi
fi

# R6 — grader-owned /api/aqi assertion against the aqi-fixture "normal"
# scenario: all eight values, derived from grading/fixtures/normal.json at
# run time (see grading/assert_aqi.py) — never hardcoded here.
if ! $COMPOSE_READY; then
  record "aqi_normal" "FAIL" "make docker compose up -d --build serve port 56733, then add GET /api/aqi"
else
  run_bounded 60 docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/normal fastapi uv run python /grading/assert_aqi.py normal > /tmp/w08-aqi-normal-$$.log 2>&1
  if [ "$?" -eq 0 ]; then
    record "aqi_normal" "PASS" "$(tail -1 /tmp/w08-aqi-normal-$$.log)"
  else
    record "aqi_normal" "FAIL" "$(tail -1 /tmp/w08-aqi-normal-$$.log) — inspect /tmp/w08-aqi-normal-$$.log"
  fi
fi

# R7 — grader-owned /api/aqi assertion against the "boundary" scenario,
# where the current hour is the LAST entry in hourly.time. Contract: 200,
# current exact, next_hr is JSON null. A naive `hourly.time.index(t) + 1`
# raises IndexError here (bare 500 -> FAIL).
if ! $COMPOSE_READY; then
  record "aqi_boundary" "FAIL" "make docker compose up -d --build serve port 56733, then add GET /api/aqi"
else
  run_bounded 60 docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/boundary fastapi uv run python /grading/assert_aqi.py boundary > /tmp/w08-aqi-boundary-$$.log 2>&1
  if [ "$?" -eq 0 ]; then
    record "aqi_boundary" "PASS" "$(tail -1 /tmp/w08-aqi-boundary-$$.log)"
  else
    record "aqi_boundary" "FAIL" "$(tail -1 /tmp/w08-aqi-boundary-$$.log) — return next_hr: null when there is no next hour, don't let hourly.time.index(...) + 1 run past the end of the list"
  fi
fi

# R8 — Vite and Vue scaffold, with no old jQuery code.
vite_reason=$(run_python - <<'PY'
from pathlib import Path
import json

path = Path("frontend/package.json")
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    print("create valid frontend/package.json with the Vue Vite scaffold")
    raise SystemExit(1)
all_deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
missing = [name for name in ("vue", "@vitejs/plugin-vue") if name not in all_deps]
if missing:
    print("add missing frontend packages: " + ", ".join(missing))
    raise SystemExit(1)
print("ok")
PY
)
jquery_file=$(find frontend -path 'frontend/node_modules' -prune -o -type f -exec grep -Eil 'jquery' {} + 2>/dev/null | head -1)
APP_VUE="frontend/src/App.vue"
if [ -n "$jquery_file" ]; then
  record "vue_static" "FAIL" "remove jQuery from $jquery_file; this lab uses Vue"
elif [ "$vite_reason" != "ok" ]; then
  record "vue_static" "FAIL" "$vite_reason"
elif [ ! -f "$APP_VUE" ]; then
  record "vue_static" "FAIL" "create frontend/src/App.vue"
elif ! grep -Eq "['\"]/api/aqi['\"]" "$APP_VUE"; then
  record "vue_static" "FAIL" "fetch the literal /api/aqi path in frontend/src/App.vue"
elif ! grep -q 'v-for' "$APP_VUE"; then
  record "vue_static" "FAIL" "add v-for to frontend/src/App.vue"
elif ! grep -q '{{' "$APP_VUE"; then
  record "vue_static" "FAIL" "add {{ }} interpolation to frontend/src/App.vue"
else
  record "vue_static" "PASS" "App.vue fetches /api/aqi and renders it with v-for + {{ }}"
fi

# R9 — service-name proxy target, bound to all interfaces inside the
# container.
VITE_CONFIG="frontend/vite.config.js"
if [ -f "$VITE_CONFIG" ] \
  && grep -q 'proxy' "$VITE_CONFIG" \
  && grep -q "['\"]/api['\"]" "$VITE_CONFIG" \
  && grep -q "http://fastapi:8000" "$VITE_CONFIG" \
  && grep -q "0.0.0.0" "$VITE_CONFIG"; then
  record "proxy_config" "PASS" "Vite binds 0.0.0.0 and proxies /api to the fastapi compose service"
else
  record "proxy_config" "FAIL" "in frontend/vite.config.js: host '0.0.0.0' and proxy '/api' -> http://fastapi:8000"
fi

# R10 — direct and proxied requests must return equal JSON for the
# deterministic /api/me anchor (compose + proxy both actually working).
if ! $DOCKER_READY; then
  record "proxy_live" "FAIL" "start Docker Desktop / install Docker, then rerun bash check.sh"
elif ! $COMPOSE_READY; then
  record "proxy_live" "FAIL" "make docker compose up -d --build serve port 56733; inspect /tmp/w08-compose-$$.log"
elif ! $ME_DIRECT_OK; then
  record "proxy_live" "FAIL" "GET /api/me on 56733 must work before the proxy can forward it (Section 3)"
elif ! $PROXY_OK; then
  record "proxy_live" "FAIL" "http://localhost:8080/api/me did not return JSON — in frontend/vite.config.js add a proxy sending /api to http://fastapi:8000 (the compose service name, not 127.0.0.1). HTML back means there is no proxy block; 502 means the target is wrong"
elif run_python - /tmp/w08-me-direct-$$.json /tmp/w08-me-proxy-$$.json <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as direct_handle:
    direct = json.load(direct_handle)
with open(sys.argv[2], encoding="utf-8") as proxy_handle:
    proxy = json.load(proxy_handle)
raise SystemExit(0 if direct == proxy else 1)
PY
then
  record "proxy_live" "PASS" "GET :8080/api/me returns the same JSON as :56733/api/me"
else
  record "proxy_live" "FAIL" "make the Vite proxy return the same JSON as direct port 56733"
fi

section "Challenge (bonus — never affects required pass/fail)"

# B1 — production frontend build.
if ! command -v npm >/dev/null 2>&1; then
  record_bonus "frontend_build" "TODO" "install Node 22 and npm, then run npm ci and npm run build" ""
elif [ ! -f package-lock.json ]; then
  record_bonus "frontend_build" "TODO" "run npm install AT THE REPO ROOT so the root package-lock.json exists" ""
else
  run_bounded 240 npm ci >/tmp/w08-npm-ci-$$.log 2>&1 \
    && run_bounded 180 npm run build >/tmp/w08-npm-build-$$.log 2>&1
  build_status=$?
  if [ "$build_status" -eq 0 ] && [ -f frontend/dist/index.html ]; then
    record_bonus "frontend_build" "DONE" "npm ci and npm run build produced frontend/dist/index.html" ""
  else
    record_bonus "frontend_build" "TODO" "fix npm ci or npm run build; inspect /tmp/w08-npm-build-$$.log" ""
  fi
fi

# B2 — deployed URL. Filename is vercel_url.txt (was DEPLOY_URL.txt);
# parsing is forgiving: strip whitespace/trailing slash, skip blanks and
# # comments, take the first line starting with https://. Unreachable or
# missing is TODO, never FAIL — this is bonus and depends on a third party.
# The resolved URL is echoed back into challenge_report.json as "url" so
# every student's live deploy can be harvested in bulk.
deploy_url=""
if [ -f vercel_url.txt ]; then
  deploy_url=$(run_python - vercel_url.txt <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("https://"):
            print(line.rstrip("/"))
            break
PY
)
fi
if [ -z "$deploy_url" ]; then
  record_bonus "deployed" "TODO" "add one https:// URL line to vercel_url.txt at the repo root" ""
else
  curl --fail --silent --max-time 15 "$deploy_url/api/me" > /tmp/w08-deploy-$$.json 2>/dev/null
  deploy_status=$?
  url_field="\"url\": \"$deploy_url\""
  if [ "$deploy_status" -eq 0 ] && run_python - /tmp/w08-deploy-$$.json <<'PY' >/dev/null 2>&1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
raise SystemExit(0 if isinstance(data, dict) and "name" in data else 1)
PY
  then
    record_bonus "deployed" "DONE" "$deploy_url/api/me returns a JSON object" "$url_field"
  else
    record_bonus "deployed" "TODO" "make $deploy_url/api/me return HTTP 200 with a JSON object" "$url_field"
  fi
fi

# B3–B6 — designed-to-break AQI payloads, graded against the binding error
# contract (see grading/assert_aqi.py): nulls -> 200 passthrough;
# not_in_list/upstream_down/malformed -> 502 with a JSON "error" key.
bonus_aqi_scenario() {
  local check_name=$1 scenario=$2 hint=$3
  if ! $COMPOSE_READY; then
    record_bonus "$check_name" "TODO" "start the app and add GET /api/aqi" ""
    return
  fi
  run_bounded 60 docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/$scenario fastapi uv run python /grading/assert_aqi.py "$scenario" > /tmp/w08-aqi-$scenario-$$.log 2>&1
  if [ "$?" -eq 0 ]; then
    record_bonus "$check_name" "DONE" "$(tail -1 /tmp/w08-aqi-$scenario-$$.log)" ""
  else
    record_bonus "$check_name" "TODO" "$hint" ""
  fi
}
bonus_aqi_scenario "aqi_nulls" "nulls" "pass null us_aqi/pm2_5 values through with 200, don't crash on them"
bonus_aqi_scenario "aqi_not_in_list" "not_in_list" "return 502 + {\"error\": ...} when current.time is missing from hourly.time"
bonus_aqi_scenario "aqi_upstream_down" "upstream_down" "return 502 + {\"error\": ...} when the upstream host answers with an error status"
bonus_aqi_scenario "aqi_malformed" "malformed" "return 502 + {\"error\": ...} when the upstream body is not valid JSON"

# B7 — the HW01-style hourly table: /api/hourly returns >= 12 readings, and
# App.vue renders them in a <table>.
if ! $COMPOSE_READY; then
  record_bonus "hourly_table" "TODO" "start the app and add GET /api/hourly" ""
else
  run_bounded 60 docker compose run --rm -T -e AQI_BASE_URL=http://aqi-fixture/normal fastapi uv run python /grading/assert_aqi.py hourly > /tmp/w08-hourly-$$.log 2>&1
  hourly_api_ok=$?
  if [ "$hourly_api_ok" -eq 0 ] && grep -q '<table' "$APP_VUE" 2>/dev/null; then
    record_bonus "hourly_table" "DONE" "$(tail -1 /tmp/w08-hourly-$$.log); App.vue renders a <table>" ""
  else
    record_bonus "hourly_table" "TODO" "add GET /api/hourly (>= 12 readings) and a <table> in App.vue rendering it" ""
  fi
fi

cleanup_compose

TOTAL=$((PASS + FAIL))
req_items=${REQ_ITEMS%,}
bonus_items=${BONUS_ITEMS%,}
{
  echo "{"
  echo "  \"score\": $PASS,"
  echo "  \"total\": $TOTAL,"
  echo "  \"results\": [$req_items]"
  echo "}"
} > "$JSON"
{
  echo "{"
  echo "  \"bonus\": $BONUS_DONE,"
  echo "  \"bonus_total\": $BONUS,"
  echo "  \"results\": [$bonus_items]"
  echo "}"
} > "$CHALLENGE_JSON"

echo ""
echo "=============================================="
echo -e "  Score: ${GREEN}${PASS}${NC} / ${TOTAL} required   |   ${RED}${FAIL}${NC} failed"
echo -e "  Bonus: ${GREEN}${BONUS_DONE}${NC} / ${BONUS} challenges"
echo "=============================================="
echo "📄 Reports: $JSON + $CHALLENGE_JSON"

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}🎉 All required checks passed! Run: bash submit.sh${NC}"
else
  echo -e "${YELLOW}⚠️  Fix required checks, then rerun bash check.sh.${NC}"
fi
echo -e "${CYAN}Bonus challenges never cause a required failure.${NC}"

exit 0
