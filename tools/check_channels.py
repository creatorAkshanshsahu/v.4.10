#!/usr/bin/env python3
"""
Channel checker for AK TV. Run it on a machine WITH internet access:

    python3 tools/check_channels.py                 # every channel (slow, ~1176)
    python3 tools/check_channels.py --limit 40      # first 40 channels
    python3 tools/check_channels.py --ids 143,167   # specific channel ids

For each channel it reads the same two feeds the app uses:
  * the TG TV public API  (sources / servers)
  * the jjtvxweb channel list (per-channel url + ClearKey keyId/key)
then requests every stream link with the headers the app sends and reports
whether it returned a real manifest (MPD or HLS playlist).

Tokens (__hdnea__) expire within about an hour, so an old jjtvxweb list will
show "expired" links. The TG API links are fresh when you run this.
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://livetgtv.lovable.app/api/public/channels"
JJ_LIST = "https://jjtvxweb.pages.dev/jstr4web.json"
UA = ("Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
DEAD_RELAY = "/jiotv-m3u/jtv.mpd"


def get(url, headers=None, timeout=12):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read(400_000)


def fetch_json(url):
    _, body = get(url, {"Accept": "application/json"})
    return json.loads(body.decode("utf-8", "replace"))


def check_stream(url, referer):
    """Returns (verdict, detail). verdict: OK, DEAD_RELAY, HTTP <code>, NOT_MANIFEST, ERROR."""
    if DEAD_RELAY in url:
        return "DEAD_RELAY", "generic relay with no channel id (answers 'invalid id')"
    headers = {}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    try:
        code, body = get(url, headers)
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code}", "refused (token expired or wrong headers)" if e.code in (401, 403, 404, 410) else str(e.reason)
    except Exception as e:  # network, DNS, timeout
        return "ERROR", str(e)[:80]
    text = body[:400].decode("utf-8", "replace").lstrip()
    if "<MPD" in body[:4000].decode("utf-8", "replace"):
        return "OK", f"MPD ({len(body)} bytes)"
    if text.startswith("#EXTM3U"):
        return "OK", f"HLS ({len(body)} bytes)"
    return "NOT_MANIFEST", text[:60].replace("\n", " ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--ids", default="")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    try:
        channels = fetch_json(API)["channels"]
    except Exception as e:
        print(f"Cannot reach the TG TV API ({e}). Run this on a machine with internet access.")
        return 2
    if args.ids:
        wanted = set(args.ids.split(","))
        channels = [c for c in channels if c["id"] in wanted]
    elif args.limit:
        channels = channels[: args.limit]
    try:
        jj = {c.get("id"): c for c in fetch_json(JJ_LIST)}
    except Exception as e:
        print(f"(jjtvxweb list unavailable: {e})")
        jj = {}

    def run(ch):
        rows = []
        try:
            detail = fetch_json(f"{API}/{ch['id']}")
        except Exception as e:
            return [(ch["name"], "api", "ERROR", str(e)[:60])]
        for u in detail.get("sources", []) or []:
            v, d = check_stream(u, None)
            rows.append((ch["name"], "TG API", v, d))
        j = jj.get(ch["id"])
        if j and j.get("url"):
            v, d = check_stream(j["url"], "https://www.jiotv.com/")
            key = " (ClearKey)" if j.get("keyId") not in (None, "null", "") else ""
            rows.append((ch["name"], "jjtvxweb" + key, v, d))
        if not rows:
            rows.append((ch["name"], "-", "NO SOURCE", ""))
        return rows

    counts = {}
    with ThreadPoolExecutor(args.workers) as ex:
        for rows in ex.map(run, channels):
            for name, src, verdict, detail in rows:
                counts[verdict] = counts.get(verdict, 0) + 1
                print(f"{verdict:12} {src:18} {name[:28]:28} {detail}")
    print("\nSummary:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
