"""Trusted intake command for the two-card Minute Clock brief. Run from the candidate root."""

from pathlib import Path
import os
import re
import subprocess
import sys


def run(*args):
    return subprocess.run(
        [sys.executable, "-B", *args],
        capture_output=True,
        timeout=30,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


valid = {"0": "0h 00m", "1": "0h 01m", "59": "0h 59m", "60": "1h 00m",
         "65": "1h 05m", "00065": "1h 05m", "9999": "166h 39m"}
invalid = [[], ["1", "2"], ["-1"], ["10000"], ["+3"], ["3.5"], ["abc"], ["１２"], [""]]
cases = [([arg], 0, (value + "\n").encode(), b"") for arg, value in valid.items()]
cases += [(args, 2, b"", b"usage: minutes.py N (0..9999)\n") for args in invalid]
for args, status, stdout, stderr in cases:
    result = run("minutes.py", *args)
    if (result.returncode, result.stdout, result.stderr) != (status, stdout, stderr):
        sys.exit(f"minutes.py failed exit/stdout/stderr check for {args!r}")
print(f"{len(cases)} CLI exit/stdout/stderr checks passed")

# Discovery runs on every card. Include named results but omit variable elapsed times
# so the captured check output can be reproduced at the published commit.
suite = run("-m", "unittest", "discover", "-v")
report = suite.stderr.decode(errors="replace")
if suite.returncode not in (0, 5):
    sys.stderr.buffer.write(suite.stdout + suite.stderr)
    sys.exit(suite.returncode)
summary = re.search(r"^Ran (\d+) tests? in [\d.]+s$", report, re.MULTILINE)
if not summary:
    sys.exit("Missing unittest discovery summary")
passed = [line for line in report.splitlines() if line.endswith(" ... ok")]
print("python3 -m unittest discover -v")
for line in passed:
    print(line)
discovered = int(summary[1])
if suite.returncode == 5 and discovered != 0:
    sys.exit("Inconsistent unittest discovery status")
print(f"Discovered {discovered} project tests, {len(passed)} passed")

readme = Path("README.md")
if "--final" in sys.argv or discovered or readme.exists() or any(Path(".").rglob("test*.py")):
    if len(passed) < 3:
        sys.exit("Expected at least three passing project tests")
    if not readme.is_file():
        sys.exit("README.md with valid and invalid examples is required")
else:
    print("README and project tests are due on the second card")
