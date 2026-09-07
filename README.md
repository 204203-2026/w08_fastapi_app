# w08_fastapi_app — Week 8 Lab: Chiang Mai Air Quality

**You build the harness before you trust the code.**

This lab has two halves. The first half is an app: a FastAPI backend and a Vue frontend showing Chiang Mai air quality. The second half is the point. `check.sh` is the self-check you run yourself. It is the start of the safety net that catches your agent's mistakes next week. You work on your own Ubuntu machine or Mac. Everything runs in Docker. No VM, no SSH, no Codespaces.

```
browser ─▶ localhost:8080 (frontend: Vite + Vue)
              │ /api/* proxied inside compose
              ▼
          fastapi:8000 (backend, also localhost:56733 on your machine)
              │ reads AQI_BASE_URL
              ├─▶ real Open-Meteo (default)
              └─▶ aqi-fixture (the grader's frozen payloads)
```

The last arrow is swappable — that is the point.

## The three commands

| you want | command |
|---|---|
| set up tools | `bash init.sh` |
| grade yourself | `bash check.sh` |
| submit | `bash submit.sh` |

`check.sh` always exits `0`. Pass and fail live in `results/report.json` and `results/challenge_report.json`, not the exit code.

## What You Will Learn

| section | skills |
|---|---|
| §1 | `uv` projects: `uv add`, runtime vs dev dependencies, the lock file |
| §2 | `docker compose`: images, `up`, logs, `--reload` through a volume mount |
| §3–§6 | Simple TDD: `TestClient`, the red-green rhythm, exact-value tests |
| §4–§5 | Call another API from your backend, reshape JSON, configuration by environment variable |
| §7–§8 | Vite + Vue scaffold, the `/api` proxy, service-name DNS, reading compose logs |
| §9 | Self-grading with `check.sh`, submission with `submit.sh` |

## Contents

1. [Getting Started (8 min)](#0-getting-started-8-min)
2. [Section 1 — Backend scaffold with uv (12 min)](#1-backend-scaffold-with-uv-12-min)
3. [Section 2 — Containers up (22 min)](#2-containers-up-22-min)
4. [Section 3 — First test: /api/me, red then green (18 min)](#3-first-test-api-me-red-then-green-18-min)
5. [Section 4 — Meet the data (18 min)](#4-meet-the-data-18-min)
6. [Section 5 — Implement /api/aqi (22 min)](#5-implement-api-aqi-22-min)
7. [Section 6 — Break it on purpose (15 min)](#6-break-it-on-purpose-15-min)
8. [Section 7 — Frontend and the proxy (22 min)](#7-frontend-and-the-proxy-22-min)
9. [Section 8 — App.vue: render the air quality (20 min)](#8-appvue-render-the-air-quality-20-min)
10. [Section 9 — Check and submit (5 min)](#9-check-and-submit-5-min)
11. [Challenges (bonus)](#challenges-bonus)
12. [Common Mistakes](#common-mistakes)
13. [Appendix: Troubleshooting](#appendix-troubleshooting)

Total: **162 minutes** of guided work. The Challenges are extra.

The frontend checks (`vue_static`, `proxy_config`, `proxy_live`) stay red until Sections 7–8. That is expected.

---

## 0. Getting Started (8 min)

**Prerequisites:** your own Ubuntu machine or Mac with:

- **Docker** — the engine and the `compose` plugin. Required infrastructure; nothing in this lab runs without it. **You do not need a GUI.** See *Docker without a GUI* just below.
- **Node ≥ 20.19** (`node --version`). Node 22 is best.
- **`uv`** — the course's Python tool. `init.sh` installs it for you if it is missing.
- **VS Code** or `nano` — either is fine, and `git`.

**Where to install each one** (course environment guide):

| tool | Ubuntu | macOS |
|---|---|---|
| `uv` | [UBUNTU.md §7](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#7-install-uv) | [MACOS.md §7](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#7-install-uv) |
| Node | [UBUNTU.md §21](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#21-nodejs-setup) | [MACOS.md §20](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#20-nodejs-setup) |
| Docker | [UBUNTU.md §25](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#25-install-docker) | [MACOS.md §24](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#24-install-orbstack-docker-for-mac) |
| lazydocker | [UBUNTU.md §26](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#26-install-lazydocker) | [MACOS.md §25](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#25-install-lazydocker) |
| `git` config | [UBUNTU.md §10](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#10-configure-git-global) | [MACOS.md §10](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#10-configure-git-global) |

`uv` in one line, if that is all you are missing:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # Ubuntu (and macOS without Homebrew)
brew install uv                                   # macOS
```

Then **open a new terminal** and check `uv --version`. A freshly installed `uv` is not
visible to the terminal that installed it.

> 💡 **Why `uv` and `node` are on your machine when everything runs in Docker.**
> Host tools *author* files; containers *run* them. `uv add` writes `pyproject.toml` and
> `uv.lock` on your machine, and `fastapi/Dockerfile` then does
> `COPY pyproject.toml uv.lock` followed by `uv sync --frozen` — so the lock file has to
> exist **before** the image can build. Moving `uv` into the Dockerfile cannot work: no
> host `uv` means no lock, which means no image. Node is the same story for the Vite
> scaffold and the root `package-lock.json`.
>
> You do **not** need `pip`, `pipx`, or `uvx` for this lab. `pip` is not used in this
> course at all (`uv` only); `pipx` and `uvx` are for standalone command-line tools, and
> this lab installs none.

**One track.** No VM, no SSH, no Codespaces. Your machine is the machine.

### Docker without a GUI

You never open a Docker dashboard in this lab. Everything is `docker compose` in the
terminal, and `lazydocker` when you want to *see* what is running. Docker Desktop is not
required on either platform.

Install from the course environment guide:

| | Docker | lazydocker |
|---|---|---|
| **Ubuntu** | [UBUNTU.md §25 — Install Docker](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#25-install-docker) | [UBUNTU.md §26 — Install lazydocker](https://github.com/kittipitch/cs111env/blob/main/UBUNTU.md#26-install-lazydocker) |
| **macOS** | [MACOS.md §24 — Install OrbStack](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#24-install-orbstack-docker-for-mac) | [MACOS.md §25 — Install lazydocker](https://github.com/kittipitch/cs111env/blob/main/MACOS.md#25-install-lazydocker) |

The short version:

```bash
# macOS — OrbStack replaces Docker Desktop, and is lighter
brew install --cask orbstack
brew install jesseduffield/lazydocker/lazydocker
```

```bash
# Ubuntu — Docker Engine + the compose plugin (full commands in UBUNTU.md §25)
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

> ⚠️ **Ubuntu, one extra step the guide does not cover.** This lab runs `docker compose`
> as *you*, never with `sudo` — `check.sh` does the same. Add yourself to the `docker`
> group once, then **log out and back in** (a new terminal is not enough; the group is
> attached at login):
> ```bash
> sudo usermod -aG docker $USER
> ```
> Verify with `docker run --rm hello-world` — **no `sudo`**. If that needs `sudo`, every
> Docker check in `check.sh` will fail.

> 💡 Ubuntu on ARM (a Raspberry Pi, or an ARM VM — check with `uname -m`): §26 downloads
> the `Linux_x86_64` lazydocker build. Take the `Linux_arm64` asset from the
> [releases page](https://github.com/jesseduffield/lazydocker/releases) instead.
> lazydocker is optional; nothing is graded on it.

**Using lazydocker:** run `lazydocker` in the repo. It lists both containers, and `l`
shows a service's logs — the same thing as `docker compose logs -f fastapi`, but you can
switch services without retyping the command. Quit with `q`.

### Create your repo

1. On GitHub, open the course org: **`204203-2026`**.
2. Open `w08_fastapi_app` and click **Use this template**.
3. Owner: **`204203-2026`**. Name: `w08_fastapi_app-STUDENTID` — replace `STUDENTID` with your 9-digit student ID.
4. Choose **Private**, then **Create repository**.

> ⚠️ Owner must be `204203-2026` and the repo must be **Private**. The grader looks only at org repos. Wrong owner or public repo = not graded.

5. Clone to your machine:
   ```bash
   git clone https://github.com/204203-2026/w08_fastapi_app-650510123.git
   cd w08_fastapi_app-650510123
   ```
   (`650510123` is an example ID. Use your own.)

### Check your tools

6. Run:
   ```bash
   bash init.sh
   ```
   You should see six green lines, one per tool, ending with:
   ```
   ✅ Tools ready. Open README.md and begin Section 1.
   ```

> 💡 `init.sh` installs `uv` automatically if it is missing. **If it did, close this terminal and open a new one before Section 1** — the current one cannot see the freshly installed `uv` yet. Check with `uv --version`.

> ⚠️ **Where you run commands.** Every command in this sheet runs **from the repo root**
> (the folder holding `README.md` and `docker-compose.yml`) unless the step explicitly
> says otherwise. When a step does send you into a subfolder, it also sends you back with
> `cd ..`. If a command ever fails with `no such file or directory` or
> `pathspec ... did not match any files`, run `pwd` first — you are probably one folder
> too deep.

**Ports** — memorize this table once. It is the map of the whole lab.

| port | reaches | what |
|---|---|---|
| `56733` | `fastapi` container | the API: `http://localhost:56733` |
| `8080` | `frontend` container | the page: `http://localhost:8080` |
| `8001` | `aqi-fixture` container | the grader's frozen payloads, browseable |
| `8000` | inside the compose network only | uvicorn's real port. Never curl it from the host |

**Your progress in `bash check.sh`** — after each section you can rerun it and watch the score rise:

| after section | score | newly green |
|---|---|---|
| Getting Started | 1/10 | `structure` |
| §1 | 2/10 | `uv_deps` |
| §2 | 3/10 | `compose_up` |
| §3 | 4/10 | `me_endpoint` |
| §5 | 5/10 | `aqi_normal` |
| §6 | 7/10 | `tests_pass`, `aqi_boundary` |
| §7 | 9/10 | `proxy_config`, `proxy_live` |
| §8 | 10/10 | `vue_static` |

---

## 1. Backend scaffold with uv (12 min)

You need a Python project before Docker has anything to build. `uv` is the course's Python tool: it manages dependencies and the lock file. **Dependency** — code your project needs, downloaded and pinned by name and version.

> ⚠️ Do not touch `requirements.txt` or `pip` in this course. `uv` only.

### Steps

1. `cd fastapi` from the repo root.

2. The starter `uv.lock` is a placeholder — one text line, not a real lock file. `uv` cannot parse it, and `uv add` refuses to run until it is gone. Remove it:
   ```bash
   rm uv.lock
   ```

3. Add your backend dependencies. **Runtime dependency** — code the app needs while it runs:
   ```bash
   uv add fastapi uvicorn httpx
   ```

   > 💡 `httpx` is a runtime dependency, not a test tool. `/api/aqi` uses it to call the air-quality service. `pytest` is different: it runs tests only, so it goes in the dev group.

4. Add the test tool. **Dev dependency** — a tool for building and testing, not for running:
   ```bash
   uv add --dev pytest
   ```
   Open `fastapi/pyproject.toml`. `dependencies` now lists `fastapi`, `uvicorn`, `httpx`, and a new `[dependency-groups]` block lists `pytest`. A new `uv.lock` file pins every downloaded package. **Lock file** — a machine-written list of every package, exact version by version. `uv add` wrote it; you never edit it.

5. Notice a block you did not type:
   ```toml
   [tool.pytest.ini_options]
   pythonpath = ["."]
   ```
   It shipped with the starter. It lets `pytest` import `main` from `tests/test_api.py` later. `uv add` preserved it. Leave it.

6. Go back to the repo root — every remaining command in this sheet expects it:
```bash
cd ..
```

7. `git status` — two files modified: `fastapi/pyproject.toml` and `fastapi/uv.lock`. (`uv` also created `fastapi/.venv/`, but it is in `.gitignore`, so `git status` does not list it.)

**Commit** (from the repo root):
```bash
git add fastapi/ && git commit -m "build(backend): scaffold uv project with fastapi, uvicorn and test deps"
```

**Next:** Section 2 (~22 min) — containers.

---

## 2. Containers up (22 min)

**Learning goal:** run the backend the only way this lab runs anything — in `docker compose` — and read a service's logs.

### Write the greeting

1. Open `fastapi/main.py`. Replace it with the smallest possible backend:
   ```python
   from fastapi import FastAPI

   app = FastAPI()

   @app.get("/")
   def home():
       return "Hello from Malee's backend"
   ```
   `Malee` is an example name. Write your own.

### Read what shipped

2. Open `fastapi/Dockerfile`:
   ```dockerfile
   FROM python:3.13-slim
   WORKDIR /app
   COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
   COPY pyproject.toml uv.lock ./
   RUN uv sync --frozen --no-dev --no-install-project
   COPY . .
   EXPOSE 8000
   CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
   ```
   Read it line by line:
   - `uv sync --frozen` — install exactly the lock file. The container gets what you committed, not whatever is newest.
   - `--host 0.0.0.0` — the container's `127.0.0.1` is its own private loopback. Without this line the published port reaches nothing.
   - `fastapi/.dockerignore` contains `.venv`. It stops `COPY . .` from pasting your host's virtualenv over the one the image just built.

3. Open `docker-compose.yml`. The lab ships it. Tour:

   | service | what it is |
   |---|---|
   | `fastapi` | your backend. Host port `56733` → container port `8000` — outside:inside, like week 7's `-p` |
   | `frontend` | your page. Port `8080`. Empty until Section 7 |
   | `aqi-fixture` | the grader's stand-in air-quality service. Section 4 explains it |
   | `volumes` | your edited files appear inside the running container. That is what keeps `--reload` alive |

4. Start the backend:
   ```bash
   docker compose up fastapi
   ```
   First run builds the image — takes a few minutes. When it ends you should see:
   ```
   INFO:     Uvicorn running on http://0.0.0.0:8000
   INFO:     Application startup complete.
   ```
   The lines carry the prefix `fastapi-1  |` — it tells you which service is talking. Soon there will be three.

5. In a **second terminal**, from the repo root:
   ```bash
   curl -i http://localhost:56733/
   ```
   You should see:
   ```
   HTTP/1.1 200 OK
   content-type: application/json
   "Hello from Malee's backend"
   ```
   Status line, content type, body — your first look at an HTTP exchange.

6. Leave the first terminal alone. Edit the greeting string in `fastapi/main.py`, save. The compose terminal prints:
   ```
   WARNING:  WatchFiles detected changes in 'main.py'. Reloading...
   INFO:     Application startup complete.
   ```
   `curl` again — new greeting. You edited on your machine. The container noticed. That is the volume mount plus `--reload`.

7. Press `Ctrl-C` in the first terminal, then run detached:
   ```bash
   docker compose up -d fastapi
   ```
   **Detached** — compose starts the container and returns your terminal. This is how you normally run the stack. Watch it:
   ```bash
   docker compose logs -f fastapi
   ```
   `logs -f` follows one service's output. This is the debugging move of the whole lab. Press `Ctrl-C` to stop following — the container keeps running, because `-d` detached it.

> ⚠️ **`curl: (7) Failed to connect ... Connection refused`** on `56733` while the container says `Up`? Someone dropped `--host 0.0.0.0` from the CMD. Restore the Dockerfile line exactly.

**Commit:**
```bash
git add fastapi/ && git commit -m "feat(api): greeting route served from docker compose"
```

**Next:** Section 3 (~18 min) — the first test.

---

## 3. First test: `/api/me`, red then green (18 min)

Next week, an agent writes code faster than you can read it. You will not catch its mistakes by reading harder. You will catch them with tests that fail loudly. This section is that habit, at its smallest.

### Write the test first

1. Make the test directory and file `fastapi/tests/test_api.py`:
   ```python
   from fastapi.testclient import TestClient
   from main import app

   client = TestClient(app)
   ```
   **`TestClient`** — a fake browser that calls your app directly in Python. No server, no port, no network.

2. Add your first test:
   ```python
   def test_me():
       resp = client.get("/api/me")
       assert resp.status_code == 200
       data = resp.json()
       assert data["name"] == "Malee Sudjai"
       assert data["student_id"] == "650510123"
   ```
   Use your own name and 9-digit ID, not the example ones.

3. Run the suite:
   ```bash
   docker compose run --rm fastapi uv run pytest -q
   ```
   **`compose run`** — a one-off command in a fresh container. `up` runs services; `run` executes one command and throws the container away.
   You should see red:
   ```
   F
   FAILED tests/test_api.py::test_me - assert 404 == 200
   1 failed, 1 warning in 0.42s
   ```
   Stop here for one sentence. **404 is the right answer right now.** A test that has never failed proves nothing — it may assert nothing. Red first is what makes green mean something.

### Then the endpoint

4. Add to `fastapi/main.py`:
   ```python
   @app.get("/api/me")
   def me():
       return {"name": "Malee Sudjai", "student_id": "650510123"}
   ```

> ⚠️ The grader rejects a `name` that still contains the shipped placeholder — `replace me`, `your name`, `your phone`, `your student`, or anything wrapped in `<`/`>`, case-insensitive. A half-edited placeholder still fails. Your real name always passes. `student_id` must be exactly 9 digits.

5. Re-run the pytest command. You should see:
   ```
   1 passed, 1 warning in 0.42s
   ```

6. Open `http://localhost:56733/docs` and try `GET /api/me` from the page. This page proves the backend works before you blame anything else.

> 💡 Why `/api/me` exists: it is tiny, it cannot break, and it needs no network. When something bigger fails later, this endpoint proves the plumbing is fine.

**Commit:**
```bash
git add fastapi/ && git commit -m "feat(api): /api/me identity endpoint with failing-first test"
```

**Next:** Section 4 (~18 min) — meet the data.

---

## 4. Meet the data (18 min)

**Learning goal:** read the upstream payload you are about to reshape, and learn the week's one configuration idea.

### Look at both upstreams

1. Open this URL in your browser — the real service:
   ```
   https://air-quality-api.open-meteo.com/v1/air-quality?latitude=18.8037949&longitude=98.9499454&current=us_aqi,pm10,pm2_5&hourly=us_aqi,pm10,pm2_5&timezone=Asia%2FBangkok
   ```
   You should see JSON with a `current` block and a big `hourly` block.

2. Now the grader's version. The `aqi-fixture` container serves frozen payloads on port `8001`. Browse:
   ```
   http://localhost:8001/normal/v1/air-quality
   ```
   You should see the same shape, frozen values:
   ```
   {"latitude":18.800003,"longitude":98.899994, ...
   ```
   **Designed payload** — data built on purpose to have known values. Frozen values mean your tests can assert exact numbers.

### The reshape contract

3. Your endpoint reads the upstream and answers:
   ```json
   {
     "current": {"AQI_US": 119, "PM10": 27.9, "PM2.5": 27.8, "Time": "2025-12-05T18:00"},
     "next_hr": {"AQI_US": 108, "PM10": 37.4, "PM2.5": 37.4, "Time": "2025-12-05T19:00"}
   }
   ```
   Your backend looks up the upstream's current time inside `hourly.time`. That index is the current hour. Index + 1 is the next hour. The key mapping:

   | upstream | your key |
   |---|---|
   | `hourly.us_aqi` | `AQI_US` |
   | `hourly.pm10` | `PM10` |
   | `hourly.pm2_5` | `PM2.5` (the dot is real) |
   | `hourly.time` | `Time` |

> 💡 These eight numbers are exact fixture values. The grader checks exactly these. Your tests will assert them word for word.

### Configuration lives outside the code

4. One new idea this week. The endpoint's upstream address is **configuration**, not code. The endpoint reads it at request time:
   ```python
   os.getenv("AQI_BASE_URL", "https://air-quality-api.open-meteo.com")
   ```
   Three ways this goes:

   | who | `AQI_BASE_URL` | result |
   |---|---|---|
   | you, developing | unset | real Open-Meteo |
   | your tests | `http://aqi-fixture/normal` | frozen numbers, exact asserts |
   | the grader | `http://aqi-fixture/<scenario>` | your grade never depends on the weather, the Wi-Fi, or Open-Meteo's uptime |

   The grader will feed your endpoint unusual data. "It worked against the real API" is not evidence it is correct. We do not trust code by reading it. We build a flow that can test it. That is this course's whole argument, in one environment variable.

5. Copy the example file and recreate the container so it reads it:
   ```bash
   cp .env.example .env
   docker compose up -d fastapi
   ```
   `.env` is in `.gitignore`. Config that differs per machine never gets committed. The `*.example` file does.

### Write test 2 before the endpoint exists

6. Add to `fastapi/tests/test_api.py`:
   ```python
   import os

   def test_aqi_normal():
       os.environ["AQI_BASE_URL"] = "http://aqi-fixture/normal"
       resp = client.get("/api/aqi")
       assert resp.status_code == 200
   ```
   `os.environ[...] = ...` is a plain assignment. Your test controls the configuration. That is why the configuration exists.
   Then assert the exact numbers (below the status assert):
   ```python
       data = resp.json()
       assert data["current"] == {
           "AQI_US": 119, "PM10": 27.9, "PM2.5": 27.8, "Time": "2025-12-05T18:00"}
       assert data["next_hr"] == {
           "AQI_US": 108, "PM10": 37.4, "PM2.5": 37.4, "Time": "2025-12-05T19:00"}
   ```
7. Run the suite:
   ```bash
   docker compose run --rm fastapi uv run pytest -q
   ```
   You should see red again:
   ```
   FAILED tests/test_api.py::test_aqi_normal - assert 404 == 200
   1 failed, 1 passed, 1 warning
   ```

> ⚠️ **Connection error to `aqi-fixture`, not a 404?** You ran `pytest` on the host. Tests run inside the container — use the `docker compose run` command above, always.

**Commit:**
```bash
git add fastapi/ && git commit -m "test(api): pin /api/aqi exact values against the normal fixture"
```

**Next:** Section 5 (~22 min) — go green.

---

## 5. Implement `/api/aqi` (22 min)

**Learning goal:** call another API from your backend, reshape its JSON, and watch an exact-value test go green.

### Your backend becomes a client

1. Until now the browser asked and you answered. Now your Python asks Open-Meteo and re-answers. Backends do this constantly. In `fastapi/main.py`, add imports at the top:
   ```python
   import os
   import httpx
   ```
2. Add the path constant and the route:
   ```python
   AQI_PATH = (
       "/v1/air-quality"
       "?latitude=18.8037949&longitude=98.9499454"
       "&current=us_aqi,pm10,pm2_5"
       "&hourly=us_aqi,pm10,pm2_5"
       "&timezone=Asia%2FBangkok"
   )

   @app.get("/api/aqi")
   def aqi():
       base = os.getenv("AQI_BASE_URL", "https://air-quality-api.open-meteo.com")
       resp = httpx.get(base + AQI_PATH)
       data = resp.json()
       hourly = data["hourly"]
       i = hourly["time"].index(data["current"]["time"])
       def reshape(n):
           h = hourly
           return {
               "AQI_US": h["us_aqi"][n],
               "PM10": h["pm10"][n],
               "PM2.5": h["pm2_5"][n],
               "Time": h["time"][n],
           }
       return {"current": reshape(i), "next_hr": reshape(i + 1)}
   ```
   The line you typed came with a hint:

   > Hint: use `list.index()` to find the current time inside `hourly.time`. The next hour's values are at `index + 1`.

3. Run the suite:
   ```bash
   docker compose run --rm fastapi uv run pytest -q
   ```
   You should see:
   ```
   2 passed, 1 warning
   ```
   Those eight numbers are exact. That is what the frozen fixture bought you.

> ⚠️ **500 and a `KeyError` in `docker compose logs fastapi`?** Your reshape keys are misspelled. `pm2_5` has an underscore, `PM2.5` has a dot. The §4 table is the reference. Read the traceback — the log-reading move from Section 2 is the tool.

### The payoff: the real sky

4. The default config points at the real service. Curl it:
   ```bash
   curl http://localhost:56733/api/aqi
   ```
   You should see live Chiang Mai air quality (your numbers will differ):
   ```
   {"current":{"AQI_US":55,"PM10":9.7,"PM2.5":9.4,"Time":"2026-09-01T03:00"},"next_hr":{...}}
   ```
   Same code, different upstream, zero edits. If the lab Wi-Fi blocks it, point `.env` at the fixture and carry on — grading never touches the live API.

5. Note for later: container environment is read at container start. After editing `.env`, run `docker compose up -d fastapi` to recreate the container.

**Commit:**
```bash
git add fastapi/ && git commit -m "feat(api): fetch and reshape open-meteo aqi behind AQI_BASE_URL"
```

**Next:** Section 6 (~15 min) — break it on purpose.

---

## 6. Break it on purpose (15 min)

**Learning goal:** designed data finds the bug that the real sky almost never shows. A bug becomes a test before it becomes a fix.

### Stage the crash

1. Your `/api/aqi` works. Now we break it — with data built to break it. This is what the grader does to your code, so we do it first, together.
2. Edit `.env` — set the fixture line to the boundary scenario:
   ```
   AQI_BASE_URL=http://aqi-fixture/boundary
   ```
   Recreate the container, then curl:
   ```bash
   docker compose up -d fastapi
   curl -i http://localhost:56733/api/aqi
   ```
   You should see a crash:
   ```
   HTTP/1.1 500 Internal Server Error
   Internal Server Error
   ```
3. Look at the traceback in the logs:
   ```bash
   docker compose logs fastapi | tail
   ```
   It ends with:
   ```
   IndexError: list index out of range
   ```
   The traceback points at your own `index + 1` line.

### Find the bug yourself

4. Open `http://localhost:8001/boundary/v1/air-quality` and look at `hourly.time`. Where is the current hour? What is `index + 1` when the current hour is the **last** entry?
5. The contract, now binding: when there is no next hour, `next_hr` is `null` and the status stays `200`. An honest "nothing yet" beats a crash.

> 💡 `null`, not an empty object, not a repeat of `current` — the grader checks for `null`.

### Test first, fix second

6. Write test 3 before the fix. Add to `fastapi/tests/test_api.py`:
   ```python
   def test_aqi_boundary():
       os.environ["AQI_BASE_URL"] = "http://aqi-fixture/boundary"
       resp = client.get("/api/aqi")
       assert resp.status_code == 200
       assert resp.json()["next_hr"] is None
   ```
7. Run the suite:
   ```bash
   docker compose run --rm fastapi uv run pytest -q
   ```
   You should see your bug reproduced as a test:
   ```
   E   IndexError: list index out of range
   1 failed, 2 passed, 1 warning
   ```
   Your test now reproduces the bug. That is what makes the fix safe.
8. Fix it. Replace the `return` line of `aqi()` with:
   ```python
       if i + 1 < len(hourly["time"]):
           nxt = reshape(i + 1)
       else:
           nxt = None
       return {"current": reshape(i), "next_hr": nxt}
   ```
9. Run the suite one more time. All three:
   ```
   3 passed, 1 warning
   ```
   A fix that breaks `normal` is not a fix. All three tests guard each other.
10. Restore `.env` to the real service line:
    ```
    AQI_BASE_URL=https://air-quality-api.open-meteo.com
    ```
    Recreate: `docker compose up -d fastapi`.

> 💡 The `index + 1` hint in Section 5 was not a trap — it is the happy path. Real code is the happy path plus the edges. The Challenge payloads probe more of them.

**Commit:**
```bash
git add fastapi/ && git commit -m "fix(api): return null next_hr when current hour is last (boundary test)"
```

**Next:** Section 7 (~22 min) — frontend and the proxy.

---

## 7. Frontend and the proxy (22 min)

**Learning goal:** scaffold the Vue app, point Vite's proxy at the backend **by service name**, and prove the whole pipe with `curl` before writing any JavaScript.

### Scaffold Vite + Vue

1. From the repo root. The scaffold refuses non-empty directories, and `frontend/` ships with starter files — so scaffold into a fresh folder, then merge:
   ```bash
   npm create vite@latest vue-tmp -- --no-interactive --template vue
   cp -R vue-tmp/. frontend/
   rm -rf vue-tmp
   ```
   You should see:
   ```
   └  Done. Now run:
   ```
   The scaffold's advice (`cd vue-tmp`, `npm install`) is not for us — we merge instead. The `cp -R vue-tmp/. frontend/` command copies scaffold files over the same-named starters and keeps the shipped `frontend/Dockerfile` and `frontend/.dockerignore`. They are not part of the scaffold, and they already work.
2. One file to fix by hand. Open `frontend/index.html` and change `<title>vue-tmp</title>` to your own page title. (The scaffold names it after the temp folder.) Leave `frontend/src/components/HelloWorld.vue` alone for now — Section 8 drops it.

### Wire the proxy

3. Replace the one-line starter `frontend/vite.config.js` with:
   ```js
   import vue from '@vitejs/plugin-vue'
   import { defineConfig } from 'vite'

   export default defineConfig({
     plugins: [vue()],
     server: {
       host: '0.0.0.0',
       port: 8080,
       proxy: { '/api': 'http://fastapi:8000' },
     },
   })
   ```
   Two ideas, one line each:
   - **The proxy.** Any request starting `/api` is handed to the backend. The browser only ever talks to port `8080`.
   - **The service name.** Inside compose, `fastapi` is a DNS name for the other container. Here `127.0.0.1` would mean the Vite container's *own* loopback — the classic mistake, and the symptom table below catches it.

### Start everything

4. Bring up all three services:
   ```bash
   docker compose up -d --build
   ```
   First build of the frontend image takes a few minutes. Then check:
   ```bash
   docker compose ps
   ```
   You should see three rows, all `Up`: `fastapi`, `frontend`, `aqi-fixture`.

   | you want | command | you should see |
   |---|---|---|
   | everything, live | `docker compose logs -f` | interleaved lines: `fastapi-1 |`, `frontend-1 |` prefixes |
   | one half, isolated | `docker compose logs -f fastapi` | just that service |
   | which halves are up | `docker compose ps` | three `Up` rows |

   Two servers used to mean two terminals babysat by hand. Compose runs both. Your job moved from keeping them alive to reading their logs.

5. Open `http://localhost:8080` — the scaffold's Vue + Vite welcome page. The frontend is alive.
6. **Prove the pipe before any JavaScript.** Curl through the frontend's port:
   ```bash
   curl -i http://localhost:8080/api/me
   ```
   You should see your own JSON:
   ```
   HTTP/1.1 200 OK
   {"name":"Malee Sudjai","student_id":"650510123"}
   ```
   Port `8080` answered with port `8000`'s data: the proxy works. Because `/api/me` cannot break, any failure here is plumbing, not air quality.

### The kill drill

7. Stop the backend, keep the frontend running:
   ```bash
   docker compose stop fastapi
   curl -i http://localhost:8080/api/me
   ```
   You should see:
   ```
   HTTP/1.1 502 Bad Gateway
   ```
   Look at the frontend's logs:
   ```bash
   docker compose logs frontend | tail
   ```
   You should see:
   ```
   [vite] http proxy error: /api/me
   Error: getaddrinfo ENOTFOUND fastapi
   ```
   **502 from `8080` always means: the frontend is fine, the backend is not.**
   Restart: `docker compose start fastapi`, curl again, `200`.

8. The symptom table — when the page misbehaves, start here:

   | symptom | meaning | look at |
   |---|---|---|
   | `:8080` refuses connection entirely | frontend container down | `docker compose ps`, `logs frontend` |
   | `502` on `:8080/api/...` | backend down or crashed | `docker compose logs fastapi` |
   | `502` via `:8080` but `:56733` works and `logs fastapi` is quiet | proxy target wrong — `127.0.0.1` instead of `fastapi` | `vite.config.js` |
   | `:8080/api/...` returns HTML instead of JSON | no `proxy` block at all — Vite served the page instead | `vite.config.js` |
   | `500` on `/api/...` | your Python raised | the traceback in `logs fastapi` |
   | container `Up` but its port refuses | dropped `--host 0.0.0.0` | the Dockerfile CMD |

   Debugging order, outward from the backend: `docker compose ps` → curl `:56733` direct → curl `:8080` through the proxy → browser Console.

**Commit:**
```bash
git add frontend/ && git commit -m "build(frontend): vite scaffold with compose-internal /api proxy"
```

**Next:** Section 8 (~20 min) — render the data.

---

## 8. App.vue: render the air quality (20 min)

**Learning goal:** one component fetches `/api/aqi` and renders both blocks.

Same five Vue names as Monday — `createApp`, `data`, `mounted`, `v-for`, `{{ }}` — new addresses. `index.html` is the frame. `main.js` does `createApp`. One `.vue` file is `<template>` plus `<script>` in the same file.

1. Replace `frontend/src/App.vue` entirely with the file below (this also drops the scaffold's `HelloWorld.vue` import — you can now `rm frontend/src/components/HelloWorld.vue`):
   ```vue
   <template>
     <h1>Chiang Mai Air Quality</h1>
     <div v-for="(block, label) in aqi" :key="label">
       <h2>{{ label }}</h2>
       <p>AQI (US): {{ block.AQI_US }}</p>
       <p>PM10: {{ block.PM10 }}</p>
       <p>PM2.5: {{ block["PM2.5"] }}</p>
       <p>Time: {{ block.Time }}</p>
     </div>
   </template>

   <script>
   export default {
     data() {
       return { aqi: { current: {}, next_hr: {} } }
     },
     async mounted() {
       const resp = await fetch('/api/aqi')
       this.aqi = await resp.json()
     },
   }
   </script>
   ```
2. Glosses, one line each:
   - `v-for` over an object walks (value, key) pairs. Monday it walked a list. Same directive.
   - `PM2.5` has a dot, so bracket lookup: `block["PM2.5"]`, never `block.PM2.5`.
   - The empty init `{}` is the design: the cards render empty first. An empty card means: ask where the data went.
3. Save. Vite hot-reloads:
   ```
   frontend-1  | page reload src/App.vue
   ```
   Open `http://localhost:8080`. First you see two labelled cards with blank values. Then the `mounted` fetch fills them with live values.

4. Prove the split. Flip `.env` to `AQI_BASE_URL=http://aqi-fixture/normal`, run `docker compose up -d fastapi`, refresh the page. The cards show the exact eight numbers from Section 4. One config line changed what the page says. Nothing else moved. Flip `.env` back to the real service and recreate.
5. Kill drill with the page open: `docker compose stop fastapi`, refresh `http://localhost:8080`. You see the heading and two empty cards. DevTools **Network** tab shows `/api/aqi` red `502`. **Empty cards + a red Network row = backend problem, not a Vue problem.** Start it: `docker compose start fastapi`.

> ⚠️ No jQuery anywhere in `frontend/`. The grader fails any file containing it. This lab uses Vue.

> ⚠️ Blank white page plus Vite's error overlay naming `App.vue`? Read the line number it names first — usually an unclosed tag or a missing comma between `data()` and `mounted()`.

**Commit:**
```bash
git add frontend/ && git commit -m "feat(frontend): render current and next-hour aqi cards"
```

**Next:** Section 9 (~5 min) — check and submit.

---

## 9. Check and submit (5 min)

1. Grade yourself:
   ```bash
   bash check.sh
   ```
   It builds, starts the stack, runs your tests, and probes your endpoints — including the fixture scenarios. Wait for the banner:
   ```
   Score: 10 / 10 required   |   0 failed
   Bonus: 1 / 7 challenges
   ```
   (The bonus count varies. Zero is fine.)

   > 💡 `check.sh` shuts the whole stack down when it finishes, so `localhost:8080` will refuse a connection afterwards. That is expected. To keep working or to demo the app, start it again with `docker compose up -d`.
2. Submit:
   ```bash
   bash submit.sh
   ```
   It commits your work and pushes to GitHub. CI reruns everything and commits the authoritative results itself. A hand-edited `results/report.json` gets overwritten — the signal cannot be faked.

### How every check maps to your work

| check | what it wants | earned in |
|---|---|---|
| `structure` | all required files exist | ships with the template; keep them all |
| `uv_deps` | `fastapi`, `uvicorn`, `httpx` runtime + `pytest` dev, non-empty `uv.lock` | §1 |
| `compose_up` | `docker compose up` serves `GET /` on `56733` | §2 |
| `me_endpoint` | `GET /api/me`: real name, 9-digit ID | §3 |
| `tests_pass` | your pytest: exit 0 **and** `>= 3 passed` | §3–§6 |
| `aqi_normal` | all eight values exact vs the `normal` fixture | §4–§5 |
| `aqi_boundary` | `next_hr` is JSON `null` on the boundary payload | §6 |
| `vue_static` | `vue` + `@vitejs/plugin-vue`, no `jquery`; `App.vue` has `v-for`, `{{ }}`, `fetch('/api/aqi')` | §7–§8 |
| `proxy_config` | `vite.config.js`: `host: '0.0.0.0'`, proxy `/api` → `http://fastapi:8000` | §7 |
| `proxy_live` | `:8080/api/me` returns the same JSON as `:56733/api/me` | §7 |

> 💡 The grader runs your three tests **and** its own independent HTTP probes against the live app. Three `assert True` tests pass nothing: the grader's own probes would still fail you. That is the anti-fake design.

> 💡 Why so strict? Next week an agent writes more code than you can review. You will not catch its mistakes by reading harder. You will catch them because you built `check.sh` — the safety net that catches your agent's mistakes next week.

---

## Challenges (bonus)

Bonus never affects the required score. Right after Section 9 you have 1/7 — `aqi_nulls` already passes, because your Section 5 code passes nulls straight through. The other six stay TODO until you do the challenges below. Skip all of them and you still get 10/10.

**With 30 minutes left:** do A, then B, in order. Highest points per minute.

### A. Build for production — `frontend_build` (~5 min, 1 pt)

<details>
<summary><strong>Challenge A spec</strong></summary>

The root `package.json` runs `npm ci && npm run build` at the repo root, which builds `frontend/` into `frontend/dist/`. The check needs a root `package-lock.json` first:

```bash
npm install
bash check.sh
```

`npm install` at the repo root creates `package-lock.json` (workspace setup). The check then runs `npm ci` and `npm run build` itself. You should see `frontend/dist/index.html` exist, and `⭐ frontend_build BONUS` in `check.sh`.

Gloss: `dist` — the production build output. Built by the check, never committed (`.gitignore` has `dist/`).

</details>

### B. The four unfriendly payloads — `aqi_nulls`, `aqi_not_in_list`, `aqi_upstream_down`, `aqi_malformed` (~6–10 min each, 1 pt each)

<details>
<summary><strong>Challenge B spec</strong></summary>

The fixture serves four more scenarios. Browse each at `http://localhost:8001/<scenario>/v1/air-quality`:

   | scenario | the data does this | your endpoint must |
   |---|---|---|
   | `nulls` | some `us_aqi`/`pm2_5` values are `null` | answer 200 and pass the `null` values through |
   | `not_in_list` | `current.time` is missing from `hourly.time` | answer 502 with `{"error": ...}` |
   | `upstream_down` | the upstream answers `503` | answer 502 with `{"error": ...}` |
   | `malformed` | the body is not valid JSON | answer 502 with `{"error": ...}` |

   The §6 contract rules all four: nulls are data (200, pass them through). Everything else that breaks the reshape is a 502 with an `error` key. Never a traceback.
   Hints, no code: `.index()` raises `ValueError` when the time is missing. Bad JSON raises `json.JSONDecodeError`. An error status is the one that does **not** raise on its own — `httpx.get()` happily returns a `503` response object, so add `resp.raise_for_status()` right after the fetch to turn it into an `httpx.HTTPStatusError`. With that line in place, one `try/except` around fetch and find, returning `JSONResponse(status_code=502, content={"error": str(exc)})`, covers all three. `JSONResponse` is not imported yet — add `from fastapi.responses import JSONResponse` at the top of `main.py`, or you get a `NameError` and a 500 instead of your 502.
   `aqi_nulls` may already pass — your Section 5 code passes nulls through. Try it first.

</details>

### C. Publish it — `deployed` (~20 min, 1 pt)

<details>
<summary><strong>Challenge C spec</strong></summary>

Deploy to Vercel, then tell the grader where you live. Create **`vercel_url.txt` at the repo root** — exact filename, one `https://` line, blank lines and `#` comments skipped, trailing slash stripped.

   The check fetches `<url>/api/me` and wants a JSON object with your `name` in it — the deployed backend must answer. The grader echoes your URL into `results/challenge_report.json` as a `"url"` field, so your instructor can harvest every live URL in one pass.
   Unreachable or still building is `TODO`, never `FAIL` — deployment depends on a third party.

   The shipped `vercel.json` routes `/api/*` to the Python function and everything else to the static SPA. The build uses the root `package.json` (`@vercel/static-build` + `@vercel/python`). The deployed `/api/aqi` calls the real Open-Meteo — fine to demo, never graded. The grader hits `/api/me` because it is deterministic.
   Your instructor can see your URL in `results/challenge_report.json`. One line, no hunting.

</details>

### D. The hourly table — `hourly_table` (~25 min, 1 pt)

<details>
<summary><strong>Challenge D spec</strong></summary>

Add `GET /api/hourly` to `fastapi/main.py`: a JSON list of the next 12 readings from the current hour forward (fewer if the list ends). Same four keys per reading: `AQI_US`, `PM10`, `PM2.5`, `Time`.
   In `App.vue`, render it in a `<table>` under the cards — `v-for` over a real list this time, `:key="row.Time"`.
   The check grades `/api/hourly` against the `normal` fixture, then greps `App.vue` for `<table`. Both must pass.
   The §6 guard applies here too: if the current hour is near the end, return what exists — never crash.

</details>

## Common Mistakes

**Placeholder name left in.** The grader rejects `name` values still holding the shipped placeholder text (`replace me`, `your name`, `your phone`, `your student`, or `<...>`). Half-editing it still fails — put your own full name in.

**`student_id` not 9 digits.** The grader wants exactly `[0-9]{9}`.

**Proxy target `127.0.0.1`.** Inside compose, `http://127.0.0.1:8000` is the Vite container's own loopback. Use `http://fastapi:8000`.

**Edited `.env` but nothing changed.** Container environment is read at container start. Run `docker compose up -d fastapi` to recreate.

**Ran pytest on the host.** `uv run pytest` on the host cannot reach `aqi-fixture` — that DNS name only exists inside compose. Always `docker compose run --rm fastapi uv run pytest -q`.

**`uv add` fails with a TOML parse error.** You skipped Section 1's `rm uv.lock`. The starter lock is a placeholder. Remove it and re-run `uv add`.

**`vercel_url.txt` in the wrong place.** Repo root, exact filename — not inside `fastapi/` or `frontend/`. The grader opens `<repo-root>/vercel_url.txt`.

**Any jQuery in `frontend/`.** The `vue_static` check fails the whole repo on one `jquery` match. This lab is Vue only.

**Wrote `block.PM2.5` in `App.vue`.** The dot breaks JavaScript lookup. Use `block["PM2.5"]`.

---

## Appendix: Troubleshooting

<details>
<summary><strong>Open the troubleshooting appendix</strong></summary>

**Docker daemon not running.** `check.sh` reports "start Docker Desktop / install Docker". On macOS, open Docker Desktop and wait for the whale icon. On Ubuntu: `sudo systemctl start docker`, and add yourself to the `docker` group to run it without `sudo`.

**Port already allocated.** `Error starting userland proxy: listen tcp4 0.0.0.0:56733: bind: address already in use` means a previous stack is still up. Run `docker compose down`, then `docker ps` — if some container still holds the port, `docker rm -f <name>`.

**Node too old.** Vite 8 needs Node ≥ 20.19 (22 best). Check `node --version`. Ubuntu: install via `nvm` or nodesource. macOS: `brew upgrade node`. Then rerun `bash init.sh`.

**npm cache or permissions.** If `npm ci` or `npm run build` fails strangely: `npm cache clean --force`, delete `frontend/node_modules`, rerun.

**Container up but the port refuses.** A published port reaches nothing without `--host 0.0.0.0` in the container's CMD. Both Dockerfiles ship correct — do not "simplify" them.

**Page loads but no data.** Work outward: `docker compose ps`, then curl `:56733/api/me` direct, then curl `:8080/api/me` through the proxy, then the browser Console. The first step that fails names the broken half.

</details>
