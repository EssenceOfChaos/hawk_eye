# Changelog

## 0.1.0 (unreleased)

First release.

- `HawkEye.Oban` reports configured Oban workers to HawkEye heartbeat monitors through
  telemetry: success, failure on the last attempt, discards, and optionally every failed
  attempt and cancellations.
- `HawkEye.ping/2`, `HawkEye.fail/2`, `HawkEye.exit_status/3` and `HawkEye.track/3` for
  other schedulers.
- Accepts a bare ping token or a whole ping URL.
- Pings are sent in the background with two retries, never raise, and never log a full token.
