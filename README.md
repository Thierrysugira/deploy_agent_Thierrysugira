# deploy_agent

A shell script (`deploy_agent.sh`) that bootstraps, runs, and archives logs for the **Student Attendance Tracker** (`attendance_checker.py`, unmodified).

Video walkthrough: **<PASTE YOUR VIDEO LINK HERE>**

## Repository layout

```
deploy_agent_<username>/
├── deploy_agent.sh
├── README.md
├── .gitignore
└── templates/
    ├── attendance_checker.py   (unmodified)
    ├── assets.csv              (unmodified, 10 students, 4 prior sessions each)
    └── config.json             (unmodified)
```

## Requirements

- `bash`, `python3`, `zip` (the script checks for `python3` and `zip` and stops with a clear message if either is missing)

## How to run and select a feature

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh              # interactive menu (1 Deploy, 2 Run, 3 Archive, 4 Exit)
./deploy_agent.sh deploy       # Feature 1 directly
./deploy_agent.sh run          # Feature 2 directly
./deploy_agent.sh archive      # Feature 3 directly
```

Both the menu and command-line arguments are supported.

## Feature 1: Deploy

1. **Pre-flight checks:** verifies `python3` (prints `python3 --version`), `zip`, and that all three templates exist.
2. **Project name:** asks for a name (letters, numbers, `_`, `-` only) and creates `attendance_tracker_<name>/`. If it already exists, the script asks whether to overwrite; answering anything other than `y` aborts with an error.
3. **Structure created:**

```
attendance_tracker_<name>/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
└── reports/            (starts empty; the app creates the logs)
```

4. **Roster (`Helpers/assets.csv`)**
   - **Option A:** copy N students (plus header) from `templates/assets.csv`. These rows carry 4 prior sessions, so `total_sessions` is **5**.
   - **Option B:** generate N fresh students from a name array in the script, with counts starting at 0, so `total_sessions` is **1**.
   - `total_sessions` must always be one more than the prior sessions recorded in the roster. The script keeps them consistent automatically with `sed` on the `"total_sessions"` line.
5. **Permissions:** `chmod +x attendance_checker.py` and `chmod 600 Helpers/config.json`. The resulting permissions are printed.
6. **Threshold update (optional):** asked `Update attendance alert thresholds? [y/N]`.
   - Prompts for `warning` (default 75) and `failure` (default 50).
   - Empty input uses the default. Input must be a whole number from 0 to 100, otherwise it is rejected and asked again.
   - `failure` must be lower than `warning`.
   - `sed` edits only the `"warning": <n>` and `"failure": <n>` lines in place, so the file is not reformatted or reordered.
7. **Verification:** the deploy finishes by running the application (Feature 2). A successful start proves the structure, roster, and config work together.

## Feature 2: Run

Asks for the project name, then runs `python3 attendance_checker.py` from inside `attendance_tracker_<name>/`. The app is interactive: answer `P` (present) or `A` (absent) for each student. Counts are updated in `Helpers/assets.csv` and logs are written to `reports/`.

## Feature 3: Archive logs

Asks for the project name, then archives each log that exists into its own directory with a timestamp:

```
attendance_tracker_<name>/archives/
├── attendance/attendance_YYYYMMDD_HHMMSS.log
└── absent/absent_YYYYMMDD_HHMMSS.log
```

- `reports/attendance.log` goes to `archives/attendance/`; `reports/absent.log` goes to `archives/absent/`.
- Logs are **moved**, so `reports/` is empty afterward and each archived file is unique and traceable.
- If a log does not exist (for example nobody was absent, so no `absent.log`), the script prints a warning and continues without crashing.
- A confirmation with the final paths is printed.

## Signal handling (Ctrl+C / Ctrl+Z)

During deployment, `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z) are trapped. On either signal the script:

1. Prints a message that the deployment was interrupted.
2. Zips whatever exists of the project into `attendance_tracker_<name>_archive.zip` using `zip`.
3. Deletes the incomplete `attendance_tracker_<name>/` directory.
4. Exits cleanly (exit code 130).

If the interrupt happens before the project directory is created, nothing is zipped and nothing is deleted. A pre-existing directory is never touched unless you chose to overwrite it. The traps are turned off once deployment completes, so the marking session behaves normally.

### How to test the trap

```bash
./deploy_agent.sh deploy       # name: test3
# at the "Choose A or B" prompt, press Ctrl+C   (repeat with Ctrl+Z)
ls                             # zip exists, project folder is gone
unzip -l attendance_tracker_test3_archive.zip
```

The zip contains the partial project: the folders created so far (`Helpers/`, `reports/`) and the files copied before the interrupt (for example `attendance_checker.py` and `Helpers/config.json`).

## How the deployed structure was tested

- `find attendance_tracker_<name> -type f` to confirm the layout matches the required structure.
- `ls -l` to confirm `attendance_checker.py` is executable and `config.json` is `-rw-------`.
- `cat Helpers/config.json` to confirm thresholds and `total_sessions` after an update (Option A gives 5, Option B gives 1).
- `cat Helpers/assets.csv` to confirm the roster size and starting counts.
- Running a short marking session and checking that `reports/attendance.log` and `reports/absent.log` are created and that counts in `assets.csv` increase.
- Running the archive feature and checking the timestamped files in `archives/`.
- Edge cases: deploying over an existing directory (overwrite and abort), invalid threshold input such as `abc`, and Ctrl+C / Ctrl+Z mid-deploy.
