# Changelog

## 0.1.1

Documentation only; no code changes.

- Says up front that the package needs a free HawkEye account, with a link to create one.
- Step 1 of the setup links straight to the form for a new heartbeat monitor.
- Links to the HawkEye page for Elixir and the heartbeat monitoring guide.
- Says where a failure's error message is shown: the monitor's ping log, not the alert.

## 0.1.0

First release.

- `HawkEye.Oban` reports configured Oban workers to HawkEye heartbeat monitors through
  telemetry: success, failure on the last attempt, discards, and optionally every failed
  attempt and cancellations.
- `HawkEye.ping/2`, `HawkEye.fail/2`, `HawkEye.exit_status/3` and `HawkEye.track/3` for
  other schedulers.
- Accepts a bare ping token or a whole ping URL.
- Pings are sent in the background with two retries, never raise, and never log a full token.
