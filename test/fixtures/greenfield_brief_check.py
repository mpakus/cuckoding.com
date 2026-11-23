"""Check every documented greeting CLI behavior from the current checkout."""
import subprocess
import sys

cases = [
    ([], 0, b"hello\n", b""),
    (["Ada Lovelace"], 0, b"hello, Ada Lovelace\n", b""),
    (["Ada", "Lovelace"], 2, b"", b"usage: hello.py [name]\n"),
]
failed = []
for args, code, stdout, stderr in cases:
    proc = subprocess.run([sys.executable, "hello.py", *args], capture_output=True, timeout=5)
    if (proc.returncode, proc.stdout, proc.stderr) != (code, stdout, stderr):
        failed.append(f"brief requirement failed for arguments {args}")

if failed:
    sys.exit("\n".join(failed))

print("3/3 brief requirements passed")
