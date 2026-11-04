#!/usr/bin/env python3
"""Generates assets/adblock/rules.json, the ad blocking of the sites inside the
app on the computer, in WebKit's content blocker format.

Run it to update the list (Peter Lowe's ad and tracking server list), then rebuild.
The download is treated as data: only well-formed domain names become rules.
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

LIST_URL = (
    "https://pgl.yoyo.org/adservers/serverlist.php"
    "?hostformat=nohtml&showintro=0&mimetype=plaintext"
)
OUTPUT = Path(__file__).resolve().parent.parent / "assets/adblock/rules.json"
DOMAIN = re.compile(r"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$")

# WebKit refuses a list above this size.
MAX_RULES = 50000

# Empty boxes the blocked ads would leave behind.
AD_SLOTS = ", ".join(
    [
        "ins.adsbygoogle",
        ".adsbygoogle",
        "[id^='google_ads_']",
        "[id^='div-gpt-ad']",
        "iframe[src*='doubleclick.net']",
        "iframe[src*='googlesyndication.com']",
    ]
)


def main() -> None:
    request = urllib.request.Request(LIST_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        text = response.read().decode("utf-8", "replace")

    domains = sorted(
        {
            line.strip().lower()
            for line in text.splitlines()
            if DOMAIN.match(line.strip().lower())
        }
    )
    if len(domains) < 1000:
        sys.exit(f"Only {len(domains)} domains: the download looks wrong.")

    rules = [
        {
            "trigger": {
                "url-filter": "^https?://([^/]*\\.)?"
                + re.escape(domain).replace("\\.", "\\.")
                + "[:/]",
                # A site's own requests are never blocked.
                "load-type": ["third-party"],
            },
            "action": {"type": "block"},
        }
        for domain in domains[: MAX_RULES - 1]
    ]
    rules.append(
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": AD_SLOTS},
        }
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(rules, separators=(",", ":")) + "\n")
    print(f"{len(rules)} rules in {OUTPUT}")


if __name__ == "__main__":
    main()
