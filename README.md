[![CI](https://github.com/EssenceOfChaos/hawk_eye/actions/workflows/ci.yml/badge.svg)](https://github.com/EssenceOfChaos/hawk_eye/actions/workflows/ci.yml)

# HawkEye for Elixir

Find out when an Oban job fails, or when it silently stops running.

`hawk_eye` reports your scheduled jobs to [HawkEye](https://hawkeye.observer/elixir?utm_medium=readme&utm_source=hawk_eye&utm_campaign=elixir),
a hosted monitoring service, through its heartbeat monitors. Each monitor expects a ping every period. If a job fails on its last attempt,
HawkEye alerts you at once and keeps the error message in the monitor's ping log. If the
ping doesn't arrive at all because the cron plugin stopped, a node died or a queue was paused, HawkEye notices the missed deadline and alerts you
anyway. Nothing inside your application can report that, because whatever stopped the job
usually stops the reporting too.

- **No changes to your workers.** It listens to Oban's telemetry events.
- **Alerts on real failures only.** A failure Oban will retry isn't reported; the last attempt is.
- **Never gets in the way.** Pings are sent in the background, retried, and never raise,
  block a job or stop your application from starting.
- **No extra HTTP client.** It uses Erlang's built-in `:httpc` with certificate verification,
  and depends only on `:telemetry`.

## Before you start

The package sends pings; HawkEye watches the deadlines and sends the alerts, so you need a
HawkEye account. [Create a free account](https://hawkeye.observer/register?utm_medium=readme&utm_source=hawk_eye&utm_campaign=elixir): no credit
card, and the Free plan includes 5 monitors. No API key is needed.

## Installation

```elixir
def deps do
  [
    {:hawk_eye, "~> 0.1"}
  ]
end
```

## Setup

**1. [Create a heartbeat monitor](https://hawkeye.observer/monitors/new?type=heartbeat&utm_medium=readme&utm_source=hawk_eye&utm_campaign=elixir)**
in HawkEye for each scheduled worker (or Monitors → Monitor a cron job). Set the period to
how often the job runs and the grace time to how late it may finish, then copy its ping URL.

**2. Map each worker to its ping URL**, usually from environment variables:

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :hawk_eye,
    oban: [
      workers: %{
        MyApp.Workers.NightlyReport => System.get_env("HAWKEYE_NIGHTLY_REPORT"),
        MyApp.Workers.SyncInvoices => System.get_env("HAWKEYE_SYNC_INVOICES")
      }
    ]
end
```

That's all. The handler is attached when your application starts. A worker whose
environment variable isn't set is skipped with a warning.

## What gets reported

| Job outcome                | Sent to HawkEye                                        |
| -------------------------- | ------------------------------------------------------ |
| Succeeded                  | success, with how long it took                         |
| Failed, will be retried    | nothing (or a failure, with `fail_on: :every_attempt`) |
| Failed on its last attempt | failure, with the error message                        |
| Discarded by the worker    | failure                                                |
| Canceled                   | nothing (configurable with `cancelled:`)               |
| Snoozed                    | nothing                                                |
| Never ran                  | nothing, so HawkEye alerts when the deadline passes    |

Job arguments are never sent. To send only the worker name and attempt number, without the
error message, set `include_error: false`.

## Options

```elixir
config :hawk_eye,
  oban: [
    workers: %{MyApp.Workers.NightlyReport => "..."},
    fail_on: :final_attempt,   # or :every_attempt
    cancelled: :ignore,        # or :success, :fail
    include_error: true,
    include_duration: true
  ],
  enabled: true                # false turns every ping into a no-op
```

## Other schedulers

For Quantum jobs, GenServer timers or release tasks, wrap the work:

```elixir
HawkEye.track(System.get_env("HAWKEYE_CLEANUP"), fn ->
  MyApp.Cleanup.run()
end)
```

`track/2` reports success when the function returns and failure when it raises, throws or
exits (then reraises). You can also report directly with `HawkEye.ping/2`,
`HawkEye.fail/2` and `HawkEye.exit_status/3`.

## Which jobs to monitor

Heartbeats are for jobs that should run on a schedule: nightly reports, hourly syncs, cleanup
tasks. Don't list a worker that runs thousands of times a minute, because HawkEye accepts
about one ping a second per monitor. To watch a busy queue, schedule a small job that checks
the queue and reports it instead.

## Learn more

- [HawkEye for Elixir and Oban](https://hawkeye.observer/elixir?utm_medium=readme&utm_source=hawk_eye&utm_campaign=elixir)
- [Heartbeat monitoring guide](https://hawkeye.observer/docs/cron-job-monitoring?utm_medium=readme&utm_source=hawk_eye&utm_campaign=elixir): deadlines,
  grace time, alerts and the ping log

## License

MIT. See [LICENSE](LICENSE).
