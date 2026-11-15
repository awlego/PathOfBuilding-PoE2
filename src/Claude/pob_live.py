"""Run Lua inside the running Path of Building instance (Claude harness live channel).

PoB polls <live dir>/req_*.lua every ~150 ms, runs the chunk on the UI thread with helpers
(`pob`, `build`, `print`), and writes <live dir>/res_<id>.txt. This script does the round trip.

Usage:
  python pob_live.py --dir <live dir> "return pob.stat('Life', 'TotalDPS')"
  python pob_live.py --dir <live dir> -f script.lua
  echo "print(pob.stats())" | python pob_live.py --dir <live dir> -

Exit code: 0 on success, 1 on Lua error, 2 on timeout (PoB not running or panel closed).
"""
import argparse
import os
import sys
import time
import uuid


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ClaudeData", "live"))
    ap.add_argument("-f", "--file", help="read Lua from this file")
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("code", nargs="?", help="Lua code, or - for stdin")
    args = ap.parse_args()

    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            code = fh.read()
    elif args.code == "-" or args.code is None:
        code = sys.stdin.read()
    else:
        code = args.code
    if not code.strip():
        ap.error("no Lua code given")

    live = os.path.abspath(args.dir)
    if not os.path.isdir(live):
        print(f"Live dir {live} does not exist - is PoB running with the Claude panel?", file=sys.stderr)
        return 2
    rid = time.strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:8]
    tmp = os.path.join(live, f"req_{rid}.tmp")
    req = os.path.join(live, f"req_{rid}.lua")
    res = os.path.join(live, f"res_{rid}.txt")
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(code)
    os.replace(tmp, req)

    deadline = time.time() + args.timeout
    while time.time() < deadline:
        if os.path.exists(res):
            with open(res, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            try:
                os.remove(res)
            except OSError:
                pass
            status, _, body = text.partition("\n")
            sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
            print(body)
            return 0 if status == "OK" else 1
        time.sleep(0.05)
    try:
        os.remove(req)
    except OSError:
        pass
    print("Timed out waiting for PoB. Is a build open in PoB with the live channel enabled?", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
