#!/usr/bin/env python3
"""Codex CLI usage tracker.

Collects usage metrics from local Codex session jsonl files and produces a
snapshot JSON that can be consumed by other tools (for example, a menu bar app).
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

APP_LABEL = "com.codex.usage-tracker"

DEFAULT_CODEX_HOME = Path.home() / ".codex"
DEFAULT_TRACKER_DIR = DEFAULT_CODEX_HOME / "usage_tracker"
DEFAULT_CONFIG_PATH = DEFAULT_TRACKER_DIR / "config.json"
DEFAULT_SNAPSHOT_PATH = DEFAULT_TRACKER_DIR / "latest_snapshot.json"
DEFAULT_PLIST_PATH = Path.home() / "Library/LaunchAgents/com.codex.usage-tracker.plist"
DEFAULT_LOG_PATH = DEFAULT_TRACKER_DIR / "launchd.log"

DEFAULT_SESSION_WINDOW_MINUTES = 300
DEFAULT_WEEK_WINDOW_MINUTES = 10080
DEFAULT_AUTOSTART_INTERVAL_SECONDS = 180


@dataclass
class TokenUsage:
    input_tokens: int = 0
    cached_input_tokens: int = 0
    output_tokens: int = 0
    reasoning_output_tokens: int = 0
    total_tokens: int = 0

    @classmethod
    def from_mapping(cls, value: dict[str, Any] | None) -> "TokenUsage":
        if not isinstance(value, dict):
            return cls()
        return cls(
            input_tokens=_safe_int(value.get("input_tokens")),
            cached_input_tokens=_safe_int(value.get("cached_input_tokens")),
            output_tokens=_safe_int(value.get("output_tokens")),
            reasoning_output_tokens=_safe_int(value.get("reasoning_output_tokens")),
            total_tokens=_safe_int(value.get("total_tokens")),
        )

    def add(self, other: "TokenUsage") -> None:
        self.input_tokens += other.input_tokens
        self.cached_input_tokens += other.cached_input_tokens
        self.output_tokens += other.output_tokens
        self.reasoning_output_tokens += other.reasoning_output_tokens
        self.total_tokens += other.total_tokens

    def delta(self, previous: "TokenUsage") -> "TokenUsage":
        # Guard against session restarts or malformed data where totals go down.
        return TokenUsage(
            input_tokens=max(0, self.input_tokens - previous.input_tokens),
            cached_input_tokens=max(0, self.cached_input_tokens - previous.cached_input_tokens),
            output_tokens=max(0, self.output_tokens - previous.output_tokens),
            reasoning_output_tokens=max(0, self.reasoning_output_tokens - previous.reasoning_output_tokens),
            total_tokens=max(0, self.total_tokens - previous.total_tokens),
        )

    def to_dict(self) -> dict[str, int]:
        return {
            "input_tokens": int(self.input_tokens),
            "cached_input_tokens": int(self.cached_input_tokens),
            "output_tokens": int(self.output_tokens),
            "reasoning_output_tokens": int(self.reasoning_output_tokens),
            "total_tokens": int(self.total_tokens),
        }

    @property
    def has_activity(self) -> bool:
        return (
            self.input_tokens > 0
            or self.cached_input_tokens > 0
            or self.output_tokens > 0
            or self.reasoning_output_tokens > 0
            or self.total_tokens > 0
        )


@dataclass
class ParsedSession:
    session_id: str
    file_path: Path
    started_at: datetime | None
    last_event_at: datetime | None
    cli_version: str | None
    totals: TokenUsage
    events: list[tuple[datetime, TokenUsage]]
    latest_rate_limits: dict[str, Any] | None
    rate_limits_timestamp: datetime | None


class UsageTracker:
    def __init__(self, codex_home: Path, config_path: Path) -> None:
        self.codex_home = codex_home.expanduser().resolve()
        self.config_path = config_path.expanduser()
        self.config = self._load_config(self.config_path)

        self.session_window_minutes = _safe_int(
            self.config.get("session_window_minutes"), DEFAULT_SESSION_WINDOW_MINUTES
        )
        self.week_window_minutes = _safe_int(
            self.config.get("week_window_minutes"), DEFAULT_WEEK_WINDOW_MINUTES
        )

        self.session_limit_tokens = _safe_int_or_none(self.config.get("session_limit_tokens"))
        self.week_limit_tokens = _safe_int_or_none(self.config.get("week_limit_tokens"))

    def _load_config(self, path: Path) -> dict[str, Any]:
        if not path.exists():
            return {}
        try:
            with path.open("r", encoding="utf-8") as handle:
                value = json.load(handle)
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}

    def _discover_session_files(self) -> list[Path]:
        session_root = self.codex_home / "sessions"
        archived_root = self.codex_home / "archived_sessions"

        files: list[Path] = []
        if session_root.exists():
            files.extend(sorted(session_root.rglob("rollout-*.jsonl")))
        if archived_root.exists():
            files.extend(sorted(archived_root.glob("*.jsonl")))
        return files

    def _parse_session_file(self, path: Path) -> ParsedSession | None:
        session_id = path.stem
        started_at: datetime | None = None
        last_event_at: datetime | None = None
        cli_version: str | None = None

        totals = TokenUsage()
        prev_totals: TokenUsage | None = None
        events: list[tuple[datetime, TokenUsage]] = []

        latest_rate_limits: dict[str, Any] | None = None
        rate_limits_timestamp: datetime | None = None

        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue

                    try:
                        item = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    timestamp = _parse_iso8601(item.get("timestamp"))

                    item_type = item.get("type")
                    payload = item.get("payload")
                    if not isinstance(payload, dict):
                        payload = {}

                    if item_type == "session_meta":
                        session_id = str(payload.get("id") or session_id)
                        started_at = _parse_iso8601(payload.get("timestamp")) or timestamp or started_at
                        cli_version = _safe_str(payload.get("cli_version")) or cli_version
                        if timestamp and (last_event_at is None or timestamp > last_event_at):
                            last_event_at = timestamp
                        continue

                    if item_type != "event_msg" or payload.get("type") != "token_count":
                        continue

                    if timestamp and (last_event_at is None or timestamp > last_event_at):
                        last_event_at = timestamp

                    info = payload.get("info")
                    info_dict = info if isinstance(info, dict) else {}

                    total_usage = TokenUsage.from_mapping(info_dict.get("total_token_usage"))
                    if total_usage.has_activity:
                        delta = total_usage if prev_totals is None else total_usage.delta(prev_totals)
                        prev_totals = total_usage

                        if delta.has_activity:
                            event_ts = timestamp or datetime.now(timezone.utc)
                            events.append((event_ts, delta))
                            totals.add(delta)

                    rate_limits = payload.get("rate_limits")
                    if isinstance(rate_limits, dict):
                        latest_rate_limits = rate_limits
                        rate_limits_timestamp = timestamp or rate_limits_timestamp

        except OSError:
            return None

        if not events and totals.total_tokens == 0:
            return None

        return ParsedSession(
            session_id=session_id,
            file_path=path,
            started_at=started_at,
            last_event_at=last_event_at,
            cli_version=cli_version,
            totals=totals,
            events=events,
            latest_rate_limits=latest_rate_limits,
            rate_limits_timestamp=rate_limits_timestamp,
        )

    def generate_snapshot(self) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        tz_name = datetime.now().astimezone().tzname() or "local"

        session_files = self._discover_session_files()

        parsed_sessions: list[ParsedSession] = []
        all_events: list[tuple[datetime, TokenUsage]] = []

        latest_rate_limits: dict[str, Any] | None = None
        latest_rate_limits_at: datetime | None = None

        for path in session_files:
            parsed = self._parse_session_file(path)
            if not parsed:
                continue

            parsed_sessions.append(parsed)
            all_events.extend(parsed.events)

            if parsed.latest_rate_limits and parsed.rate_limits_timestamp:
                if latest_rate_limits_at is None or parsed.rate_limits_timestamp > latest_rate_limits_at:
                    latest_rate_limits = parsed.latest_rate_limits
                    latest_rate_limits_at = parsed.rate_limits_timestamp

        all_events.sort(key=lambda pair: pair[0])

        def sum_window(minutes: int) -> TokenUsage:
            cutoff = now - timedelta(minutes=minutes)
            total = TokenUsage()
            for ts, usage in all_events:
                if ts >= cutoff:
                    total.add(usage)
            return total

        all_time_usage = TokenUsage()
        for _, usage in all_events:
            all_time_usage.add(usage)

        last_5h = sum_window(5 * 60)
        last_24h = sum_window(24 * 60)
        last_7d = sum_window(7 * 24 * 60)
        last_30d = sum_window(30 * 24 * 60)

        session_window_usage = sum_window(self.session_window_minutes)
        weekly_window_usage = sum_window(self.week_window_minutes)

        primary_rate = _safe_dict((latest_rate_limits or {}).get("primary"))
        secondary_rate = _safe_dict((latest_rate_limits or {}).get("secondary"))

        session_percent = _safe_float_or_none(primary_rate.get("used_percent"))
        weekly_percent = _safe_float_or_none(secondary_rate.get("used_percent"))

        if session_percent is None and self.session_limit_tokens and self.session_limit_tokens > 0:
            session_percent = min(100.0, (session_window_usage.total_tokens / self.session_limit_tokens) * 100.0)
        if weekly_percent is None and self.week_limit_tokens and self.week_limit_tokens > 0:
            weekly_percent = min(100.0, (weekly_window_usage.total_tokens / self.week_limit_tokens) * 100.0)

        session_resets_epoch = _safe_int_or_none(primary_rate.get("resets_at"))
        weekly_resets_epoch = _safe_int_or_none(secondary_rate.get("resets_at"))

        session_resets_at = _epoch_to_iso8601(session_resets_epoch)
        weekly_resets_at = _epoch_to_iso8601(weekly_resets_epoch)

        session_resets_in_seconds = _seconds_until_epoch(session_resets_epoch, now)
        weekly_resets_in_seconds = _seconds_until_epoch(weekly_resets_epoch, now)

        # Aggregate daily totals in local timezone.
        daily_totals: dict[str, TokenUsage] = {}
        for ts, usage in all_events:
            day_key = ts.astimezone().date().isoformat()
            bucket = daily_totals.setdefault(day_key, TokenUsage())
            bucket.add(usage)

        daily_totals_serialized: dict[str, dict[str, int]] = {
            day: usage.to_dict()
            for day, usage in sorted(daily_totals.items(), key=lambda pair: pair[0], reverse=True)
        }

        active_session: ParsedSession | None = None
        if parsed_sessions:
            active_session = max(
                parsed_sessions,
                key=lambda sess: sess.last_event_at or datetime.fromtimestamp(0, tz=timezone.utc),
            )

        top_sessions = sorted(
            parsed_sessions,
            key=lambda sess: sess.totals.total_tokens,
            reverse=True,
        )[:10]

        snapshot: dict[str, Any] = {
            "generated_at": now.isoformat().replace("+00:00", "Z"),
            "codex_home": str(self.codex_home),
            "files_scanned": len(session_files),
            "sessions_count": len(parsed_sessions),
            "events_count": len(all_events),
            "last_activity_at": _to_iso8601(
                max((ts for ts, _ in all_events), default=None)
            ),
            "windows": {
                "last_5h": last_5h.to_dict(),
                "last_24h": last_24h.to_dict(),
                "last_7d": last_7d.to_dict(),
                "last_30d": last_30d.to_dict(),
                "all_time": all_time_usage.to_dict(),
            },
            "session_window": {
                "window_minutes": self.session_window_minutes,
                "usage": session_window_usage.to_dict(),
                "used_percent": session_percent,
                "resets_at": session_resets_at,
                "resets_at_epoch": session_resets_epoch,
                "resets_in_seconds": session_resets_in_seconds,
            },
            "weekly_window": {
                "window_minutes": self.week_window_minutes,
                "usage": weekly_window_usage.to_dict(),
                "used_percent": weekly_percent,
                "resets_at": weekly_resets_at,
                "resets_at_epoch": weekly_resets_epoch,
                "resets_in_seconds": weekly_resets_in_seconds,
            },
            "rate_limits": {
                "captured_at": _to_iso8601(latest_rate_limits_at),
                "primary": {
                    "used_percent": session_percent,
                    "window_minutes": _safe_int(primary_rate.get("window_minutes"), self.session_window_minutes),
                    "resets_at_epoch": session_resets_epoch,
                    "resets_at": session_resets_at,
                },
                "secondary": {
                    "used_percent": weekly_percent,
                    "window_minutes": _safe_int(secondary_rate.get("window_minutes"), self.week_window_minutes),
                    "resets_at_epoch": weekly_resets_epoch,
                    "resets_at": weekly_resets_at,
                },
                "credits": _safe_dict((latest_rate_limits or {}).get("credits")) or None,
            },
            "active_session": {
                "session_id": active_session.session_id if active_session else None,
                "file_path": str(active_session.file_path) if active_session else None,
                "started_at": _to_iso8601(active_session.started_at) if active_session else None,
                "last_event_at": _to_iso8601(active_session.last_event_at) if active_session else None,
                "totals": active_session.totals.to_dict() if active_session else TokenUsage().to_dict(),
                "cli_version": active_session.cli_version if active_session else None,
            },
            "daily_totals": daily_totals_serialized,
            "top_sessions": [
                {
                    "session_id": item.session_id,
                    "file_path": str(item.file_path),
                    "started_at": _to_iso8601(item.started_at),
                    "last_event_at": _to_iso8601(item.last_event_at),
                    "totals": item.totals.to_dict(),
                    "cli_version": item.cli_version,
                }
                for item in top_sessions
            ],
            "config": {
                "path": str(self.config_path),
                "session_limit_tokens": self.session_limit_tokens,
                "week_limit_tokens": self.week_limit_tokens,
                "session_window_minutes": self.session_window_minutes,
                "week_window_minutes": self.week_window_minutes,
            },
            "timezone": tz_name,
        }

        return snapshot


def write_snapshot(snapshot: dict[str, Any], output_path: Path) -> None:
    output_path = output_path.expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")


def print_report(snapshot: dict[str, Any]) -> None:
    session = _safe_dict(snapshot.get("session_window"))
    weekly = _safe_dict(snapshot.get("weekly_window"))
    windows = _safe_dict(snapshot.get("windows"))

    session_usage = TokenUsage.from_mapping(_safe_dict(session.get("usage")))
    weekly_usage = TokenUsage.from_mapping(_safe_dict(weekly.get("usage")))

    print("Codex CLI Usage Tracker")
    print(f"Updated: {snapshot.get('generated_at') or 'n/a'}")
    print()

    print("Session Window")
    print(f"  window: {session.get('window_minutes') or DEFAULT_SESSION_WINDOW_MINUTES} min")
    print(f"  tokens: {_format_int(session_usage.total_tokens)}")
    if session.get("used_percent") is None:
        print("  used: n/a")
    else:
        print(f"  used: {float(session['used_percent']):.1f}%")
    print(f"  reset in: {_format_duration(session.get('resets_in_seconds'))}")
    print()

    print("Weekly Window")
    print(f"  window: {weekly.get('window_minutes') or DEFAULT_WEEK_WINDOW_MINUTES} min")
    print(f"  tokens: {_format_int(weekly_usage.total_tokens)}")
    if weekly.get("used_percent") is None:
        print("  used: n/a")
    else:
        print(f"  used: {float(weekly['used_percent']):.1f}%")
    print(f"  reset in: {_format_duration(weekly.get('resets_in_seconds'))}")
    print()

    print("Rolling Totals")
    print(f"  24h: {_format_int(_safe_int(_safe_dict(windows.get('last_24h')).get('total_tokens')))} tokens")
    print(f"  30d: {_format_int(_safe_int(_safe_dict(windows.get('last_30d')).get('total_tokens')))} tokens")
    print(f"  all-time: {_format_int(_safe_int(_safe_dict(windows.get('all_time')).get('total_tokens')))} tokens")


def print_statusline(snapshot: dict[str, Any]) -> None:
    session = _safe_dict(snapshot.get("session_window"))
    weekly = _safe_dict(snapshot.get("weekly_window"))

    session_tokens = _safe_int(_safe_dict(session.get("usage")).get("total_tokens"))
    weekly_tokens = _safe_int(_safe_dict(weekly.get("usage")).get("total_tokens"))

    session_percent = _safe_float_or_none(session.get("used_percent"))
    weekly_percent = _safe_float_or_none(weekly.get("used_percent"))

    session_text = f"5h {_format_int(session_tokens)} tok"
    weekly_text = f"7d {_format_int(weekly_tokens)} tok"

    if session_percent is not None:
        session_text = f"5h {session_percent:.1f}% ({_format_int(session_tokens)})"
    if weekly_percent is not None:
        weekly_text = f"7d {weekly_percent:.1f}% ({_format_int(weekly_tokens)})"

    reset_text = _format_duration(session.get("resets_in_seconds"))
    print(f"Codex {session_text} | {weekly_text} | reset {reset_text}")


def _run_launchctl(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, check=False)


def install_autostart(
    script_path: Path,
    plist_path: Path,
    snapshot_path: Path,
    interval_seconds: int,
    codex_home: Path,
    config_path: Path,
) -> None:
    plist_path = plist_path.expanduser()
    snapshot_path = snapshot_path.expanduser()

    plist_path.parent.mkdir(parents=True, exist_ok=True)
    snapshot_path.parent.mkdir(parents=True, exist_ok=True)

    uid = os.getuid()
    label_target = f"gui/{uid}/{APP_LABEL}"

    plist_content = {
        "Label": APP_LABEL,
        "ProgramArguments": [
            sys.executable,
            str(script_path),
            "--codex-home",
            str(codex_home),
            "--config",
            str(config_path),
            "snapshot",
            "--output",
            str(snapshot_path),
            "--quiet",
        ],
        "RunAtLoad": True,
        "StartInterval": max(30, interval_seconds),
        "WorkingDirectory": str(script_path.parent),
        "StandardOutPath": str(DEFAULT_LOG_PATH),
        "StandardErrorPath": str(DEFAULT_LOG_PATH),
        "EnvironmentVariables": {
            "PYTHONUNBUFFERED": "1",
        },
    }

    with plist_path.open("wb") as handle:
        plistlib.dump(plist_content, handle)

    _run_launchctl(["launchctl", "bootout", f"gui/{uid}", str(plist_path)])

    bootstrap = _run_launchctl(["launchctl", "bootstrap", f"gui/{uid}", str(plist_path)])
    if bootstrap.returncode != 0:
        raise RuntimeError(bootstrap.stderr.strip() or bootstrap.stdout.strip() or "launchctl bootstrap failed")

    enable = _run_launchctl(["launchctl", "enable", label_target])
    if enable.returncode != 0:
        raise RuntimeError(enable.stderr.strip() or enable.stdout.strip() or "launchctl enable failed")

    kickstart = _run_launchctl(["launchctl", "kickstart", "-k", label_target])
    if kickstart.returncode != 0:
        raise RuntimeError(kickstart.stderr.strip() or kickstart.stdout.strip() or "launchctl kickstart failed")


def uninstall_autostart(plist_path: Path) -> None:
    plist_path = plist_path.expanduser()
    uid = os.getuid()
    _run_launchctl(["launchctl", "bootout", f"gui/{uid}", str(plist_path)])
    if plist_path.exists():
        plist_path.unlink()


def autostart_status(plist_path: Path) -> tuple[bool, str]:
    uid = os.getuid()
    target = f"gui/{uid}/{APP_LABEL}"
    result = _run_launchctl(["launchctl", "print", target])
    if result.returncode == 0:
        first_line = (result.stdout or "loaded").strip().splitlines()[0]
        return True, first_line

    plist_path = plist_path.expanduser()
    if plist_path.exists():
        return False, "plist exists but service is not loaded"
    return False, "not installed"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Track Codex CLI usage from local session files")
    parser.add_argument(
        "--codex-home",
        type=Path,
        default=DEFAULT_CODEX_HOME,
        help=f"Path to Codex home (default: {DEFAULT_CODEX_HOME})",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"Tracker config JSON path (default: {DEFAULT_CONFIG_PATH})",
    )

    subparsers = parser.add_subparsers(dest="command")

    report = subparsers.add_parser("report", help="Print human-readable report")
    report.add_argument("--snapshot-output", type=Path, default=None, help="Optionally write JSON snapshot")

    snapshot = subparsers.add_parser("snapshot", help="Write JSON snapshot")
    snapshot.add_argument("--output", type=Path, default=DEFAULT_SNAPSHOT_PATH, help="Snapshot output path")
    snapshot.add_argument("--quiet", action="store_true", help="Do not print summary line")

    subparsers.add_parser("statusline", help="Print one-line status text")

    install = subparsers.add_parser("install-autostart", help="Install and enable launchd autostart")
    install.add_argument("--interval", type=int, default=DEFAULT_AUTOSTART_INTERVAL_SECONDS)
    install.add_argument("--plist", type=Path, default=DEFAULT_PLIST_PATH)
    install.add_argument("--output", type=Path, default=DEFAULT_SNAPSHOT_PATH)

    uninstall = subparsers.add_parser("uninstall-autostart", help="Remove launchd autostart")
    uninstall.add_argument("--plist", type=Path, default=DEFAULT_PLIST_PATH)

    status = subparsers.add_parser("autostart-status", help="Show launchd autostart status")
    status.add_argument("--plist", type=Path, default=DEFAULT_PLIST_PATH)

    return parser


def _safe_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _safe_str(value: Any) -> str | None:
    return str(value) if value is not None else None


def _safe_int(value: Any, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _safe_int_or_none(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _safe_float_or_none(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_iso8601(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None

    normalized = value.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(normalized)
    except ValueError:
        return None

    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _epoch_to_iso8601(value: int | None) -> str | None:
    if value is None:
        return None
    try:
        return datetime.fromtimestamp(value, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
        return None


def _seconds_until_epoch(epoch: int | None, now: datetime) -> int | None:
    if epoch is None:
        return None
    try:
        target = datetime.fromtimestamp(epoch, tz=timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None
    return int((target - now).total_seconds())


def _to_iso8601(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _format_int(value: int) -> str:
    return f"{value:,}".replace(",", " ")


def _format_duration(value: Any) -> str:
    seconds = _safe_int_or_none(value)
    if seconds is None:
        return "n/a"

    if seconds <= 0:
        return "0m"

    hours, rem = divmod(seconds, 3600)
    minutes, _ = divmod(rem, 60)

    if hours > 0:
        return f"{hours}h {minutes:02d}m"
    return f"{minutes}m"


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    command = args.command or "report"

    tracker = UsageTracker(codex_home=args.codex_home, config_path=args.config)
    snapshot = tracker.generate_snapshot()

    if command == "report":
        if args.snapshot_output:
            write_snapshot(snapshot, args.snapshot_output)
        print_report(snapshot)
        return 0

    if command == "snapshot":
        write_snapshot(snapshot, args.output)
        if not args.quiet:
            print(f"Snapshot written: {args.output}")
        return 0

    if command == "statusline":
        print_statusline(snapshot)
        return 0

    if command == "install-autostart":
        script_path = Path(__file__).resolve()
        try:
            install_autostart(
                script_path=script_path,
                plist_path=args.plist,
                snapshot_path=args.output,
                interval_seconds=args.interval,
                codex_home=args.codex_home,
                config_path=args.config,
            )
        except RuntimeError as exc:
            print(f"Autostart install failed: {exc}", file=sys.stderr)
            return 1

        print(f"Autostart installed: {args.plist}")
        print(f"Snapshot output: {args.output}")
        return 0

    if command == "uninstall-autostart":
        uninstall_autostart(args.plist)
        print(f"Autostart removed: {args.plist}")
        return 0

    if command == "autostart-status":
        loaded, details = autostart_status(args.plist)
        state = "loaded" if loaded else "not loaded"
        print(f"Autostart {state}: {details}")
        return 0 if loaded else 1

    parser.error(f"Unknown command: {command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
