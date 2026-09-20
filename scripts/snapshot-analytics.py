#!/usr/bin/env python3
"""Archive the GitHub-side counters GitHub does not keep.

GitHub exposes repository traffic (views, clones, referring sites, popular
paths) for a rolling 14-day window only, and release asset download counts as
monotonic totals with no history at all. Anything not snapshotted is gone
permanently, so this script copies both into ``analytics/``.

This is repository bookkeeping, not app telemetry. Status Trio ships no
telemetry, nothing runs on a user's machine, and the data collected here is
data GitHub already holds about this repository.

The traffic endpoints need the "Administration: read" permission, which the
default Actions ``GITHUB_TOKEN`` cannot be granted. Without a dedicated
``TRAFFIC_TOKEN`` secret the script still archives release counters and warns
instead of failing.

Usage:
    python3 scripts/snapshot-analytics.py [--repo OWNER/NAME] [--out DIR] [--date YYYY-MM-DD]
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API_ROOT = "https://api.github.com"
SCHEMA_VERSION = 1
DEFAULT_REPO = "lingyired/status-trio"
TOKEN_ENV_ORDER = ("TRAFFIC_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")
USER_AGENT = "status-trio-analytics-snapshot"


def announce(message: str) -> None:
    print(message, flush=True)


def annotate(level: str, message: str) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::{level}::{message}", flush=True)
    stream = sys.stderr if level in {"warning", "error"} else sys.stdout
    print(f"{level}: {message}", file=stream, flush=True)


class GitHubError(Exception):
    def __init__(self, endpoint: str, status: int, detail: str) -> None:
        super().__init__(f"HTTP {status} for {endpoint}: {detail}")
        self.endpoint = endpoint
        self.status = status
        self.detail = detail


class Client:
    def __init__(self, repo: str, token: str) -> None:
        self.repo = repo
        self.token = token

    def _get(self, url: str) -> tuple[object, dict]:
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {self.token}",
                "User-Agent": USER_AGENT,
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
                return payload, dict(response.headers)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace").strip()
            try:
                detail = json.loads(detail).get("message", detail)
            except json.JSONDecodeError:
                pass
            raise GitHubError(url, error.code, detail[:300]) from error
        except urllib.error.URLError as error:
            raise GitHubError(url, 0, str(error.reason)) from error

    def get(self, endpoint: str) -> object:
        url = f"{API_ROOT}/repos/{self.repo}"
        if endpoint:
            url = f"{url}/{endpoint}"
        payload, _ = self._get(url)
        return payload

    def get_all(self, endpoint: str, max_pages: int = 50) -> list:
        """Fetch every page of a list endpoint, following the Link header."""
        items: list = []
        page = 1
        while True:
            query = urllib.parse.urlencode({"per_page": 100, "page": page})
            payload, headers = self._get(f"{API_ROOT}/repos/{self.repo}/{endpoint}?{query}")
            if not isinstance(payload, list):
                raise GitHubError(endpoint, 200, "expected a JSON array")
            items.extend(payload)
            if 'rel="next"' not in headers.get("Link", ""):
                return items
            page += 1
            if page > max_pages:
                announce(f"warning: stopping at {max_pages} pages for {endpoint}")
                return items


def normalize_window(payload: dict, key: str) -> dict:
    rows = payload.get(key) or []
    return {
        "count": payload.get("count", 0),
        "uniques": payload.get("uniques", 0),
        key: [
            {
                "date": str(row.get("timestamp", ""))[:10],
                "count": row.get("count", 0),
                "uniques": row.get("uniques", 0),
            }
            for row in rows
        ],
    }


def collect(client: Client) -> tuple[dict, dict]:
    snapshot: dict = {"windows": {}, "referrers": [], "paths": [], "releases": [], "errors": {}}
    traffic_failure = None

    for endpoint, key in (("traffic/views", "views"), ("traffic/clones", "clones")):
        try:
            snapshot["windows"][key] = normalize_window(client.get(endpoint), key)
        except GitHubError as error:
            snapshot["errors"][key] = f"HTTP {error.status}: {error.detail}"
            traffic_failure = traffic_failure or error

    for endpoint, key in (
        ("traffic/popular/referrers", "referrers"),
        ("traffic/popular/paths", "paths"),
    ):
        try:
            rows = client.get(endpoint)
            if key == "referrers":
                snapshot[key] = [
                    {
                        "referrer": row.get("referrer", ""),
                        "count": row.get("count", 0),
                        "uniques": row.get("uniques", 0),
                    }
                    for row in rows
                ]
            else:
                snapshot[key] = [
                    {
                        "path": row.get("path", ""),
                        "title": row.get("title", ""),
                        "count": row.get("count", 0),
                        "uniques": row.get("uniques", 0),
                    }
                    for row in rows
                ]
        except GitHubError as error:
            snapshot["errors"][key] = f"HTTP {error.status}: {error.detail}"
            traffic_failure = traffic_failure or error

    releases = client.get_all("releases")
    snapshot["releases"] = [
        {
            "tag_name": release.get("tag_name", ""),
            "name": release.get("name", ""),
            "published_at": release.get("published_at") or "",
            "prerelease": bool(release.get("prerelease")),
            "assets": [
                {
                    "name": asset.get("name", ""),
                    "download_count": asset.get("download_count", 0),
                    "size": asset.get("size", 0),
                }
                for asset in release.get("assets") or []
            ],
        }
        for release in releases
    ]

    stats = client.get("")
    snapshot["repo_stats"] = {
        "stars": stats.get("stargazers_count", 0),
        "forks": stats.get("forks_count", 0),
        "watchers": stats.get("subscribers_count", 0),
        "open_issues": stats.get("open_issues_count", 0),
    }

    return snapshot, {"traffic_failure": traffic_failure}


def write_snapshot(out_dir: Path, day: str, snapshot: dict) -> Path:
    daily_dir = out_dir / "daily"
    daily_dir.mkdir(parents=True, exist_ok=True)
    path = daily_dir / f"{day}.json"
    path.write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    return path


def rebuild_series(out_dir: Path) -> Path:
    """Collapse every daily snapshot into one readable per-day series."""
    daily_dir = out_dir / "daily"
    series: dict[str, dict[str, object]] = {}

    for path in sorted(daily_dir.glob("*.json")):
        try:
            snapshot = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            announce(f"warning: skipping unreadable snapshot {path.name}: {error}")
            continue

        windows = snapshot.get("windows") or {}
        for metric, key in (("views", "views"), ("clones", "clones")):
            for row in (windows.get(metric) or {}).get(key, []):
                date = row.get("date")
                if not date:
                    continue
                # Later snapshots win: once a day closes its numbers are final,
                # and the newest snapshot carries the most complete window.
                series.setdefault(date, {})[f"{metric}_count"] = row.get("count", 0)
                series[date][f"{metric}_uniques"] = row.get("uniques", 0)

    out_path = out_dir / "series.csv"
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["date", "views_count", "views_uniques", "clones_count", "clones_uniques"])
        for date in sorted(series):
            row = series[date]
            writer.writerow(
                [
                    date,
                    row.get("views_count", ""),
                    row.get("views_uniques", ""),
                    row.get("clones_count", ""),
                    row.get("clones_uniques", ""),
                ]
            )
    return out_path


def summarize(snapshot: dict) -> None:
    windows = snapshot.get("windows") or {}
    for metric in ("views", "clones"):
        window = windows.get(metric)
        if window:
            announce(f"{metric}: {window['count']} total / {window['uniques']} uniques (14-day window)")
        else:
            announce(f"{metric}: unavailable ({snapshot['errors'].get(metric, 'not fetched')})")

    downloads = sum(
        asset["download_count"] for release in snapshot["releases"] for asset in release["assets"]
    )
    announce(f"releases: {len(snapshot['releases'])} with {downloads} total asset downloads")
    stats = snapshot.get("repo_stats") or {}
    announce(f"repo: {stats.get('stars', 0)} stars / {stats.get('forks', 0)} forks")

    readme_languages = [
        row for row in snapshot["paths"] if "/blob/" in row["path"] and "README" in row["path"]
    ]
    for row in readme_languages:
        announce(f"language landing page {row['path']}: {row['count']} views / {row['uniques']} uniques")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY") or DEFAULT_REPO)
    parser.add_argument("--out", default=None, help="Output directory (default: <repo root>/analytics)")
    parser.add_argument("--date", default=None, help="Snapshot label, defaults to today in UTC")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    out_dir = Path(args.out) if args.out else root / "analytics"

    token = ""
    for name in TOKEN_ENV_ORDER:
        candidate = (os.environ.get(name) or "").strip()
        if candidate:
            token = candidate
            token_source = name
            break
    else:
        annotate("error", f"no token found; set one of {', '.join(TOKEN_ENV_ORDER)}")
        return 1

    if args.repo.count("/") != 1:
        annotate("error", f"--repo must be OWNER/NAME, got {args.repo!r}")
        return 1

    fetched_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    day = args.date or fetched_at[:10]

    announce(f"snapshotting {args.repo} into {out_dir} (token: {token_source}, label: {day})")
    client = Client(args.repo, token)

    try:
        snapshot, meta = collect(client)
    except GitHubError as error:
        annotate("error", f"could not read {error.endpoint}: HTTP {error.status} {error.detail}")
        return 1

    snapshot = {
        "schema": SCHEMA_VERSION,
        "repo": args.repo,
        "fetched_at": fetched_at,
        "window_days": 14,
        **snapshot,
    }

    path = write_snapshot(out_dir, day, snapshot)
    series_path = rebuild_series(out_dir)
    summarize(snapshot)
    announce(f"wrote {path.relative_to(root) if path.is_relative_to(root) else path}")
    announce(f"wrote {series_path.relative_to(root) if series_path.is_relative_to(root) else series_path}")

    traffic_failure = meta["traffic_failure"]
    if traffic_failure is not None:
        if traffic_failure.status in {401, 403, 404}:
            annotate(
                "warning",
                "repository traffic is unavailable: the token needs the "
                "'Administration: read' permission, which GITHUB_TOKEN cannot be granted. "
                "Add a TRAFFIC_TOKEN secret to archive views/clones/referrers/paths "
                "(see docs/analytics-snapshot.md). Release counters were archived.",
            )
            return 0
        annotate("error", f"traffic request failed: HTTP {traffic_failure.status} {traffic_failure.detail}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
