defmodule HawkEye.Oban do
  @moduledoc """
  Reports Oban jobs to HawkEye heartbeat monitors, with no changes to your workers.

  Create a heartbeat monitor in HawkEye for each scheduled worker, with its period set to
  how often the job runs (and a little grace time). Then map each worker to its monitor's
  ping token or ping URL:

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

  The handler is attached when the `:hawk_eye` application starts. Workers that aren't
  listed are ignored. A worker whose token is missing (for example an unset environment
  variable) is skipped with a warning, so a configuration mistake never stops your
  application from starting.

  ## What gets reported

  | Job outcome | Reported to HawkEye |
  |---|---|
  | Succeeded (`:ok`, `{:ok, _}`) | success |
  | Failed, will be retried | nothing, unless `fail_on: :every_attempt` |
  | Failed on its last attempt | failure, with the error |
  | Discarded by the worker (`{:discard, _}`) | failure |
  | Cancelled (`{:cancel, _}`) | nothing, unless `cancelled:` says otherwise |
  | Snoozed | nothing (the job runs again later) |

  A job that never runs at all sends nothing, and HawkEye alerts when the monitor's
  deadline passes. That is what a heartbeat is for: it catches a stopped scheduler, a
  crashed node or a paused queue, which nothing inside your application can report.

  Heartbeats suit scheduled workers. Don't list a worker that runs thousands of times a
  minute: HawkEye accepts about one ping a second per monitor.

  ## Options

  * `:workers` - a map (or keyword list) of worker module, or worker name as a string, to a
    ping token or ping URL. Required.
  * `:fail_on` - `:final_attempt` (default) reports a failure only once Oban stops retrying;
    `:every_attempt` reports every failed attempt.
  * `:cancelled` - what a cancelled job reports: `:ignore` (default), `:success` or `:fail`.
  * `:include_error` - `true` (default) sends the error message with a failure, so you can
    read it in the monitor's ping log in HawkEye. `false` sends only the worker name and attempt
    number. Turn it off if your error messages may contain personal or secret data.
  * `:include_duration` - `true` (default) sends how long a successful job took.
  """

  require Logger

  alias HawkEye.Token

  @handler_id "hawk_eye-oban"
  @events [[:oban, :job, :stop], [:oban, :job, :exception]]

  @doc """
  Attaches the telemetry handler with these options, replacing any earlier configuration.

  Called for you at startup when `config :hawk_eye, oban: [...]` is set. Call it yourself
  only if you build the options in code.
  """
  @spec attach(keyword()) :: :ok | {:error, term()}
  def attach(opts) when is_list(opts) do
    config = %{
      workers: normalize_workers(Keyword.get(opts, :workers, %{})),
      fail_on: option(opts, :fail_on, [:final_attempt, :every_attempt]),
      cancelled: option(opts, :cancelled, [:ignore, :success, :fail]),
      include_error: Keyword.get(opts, :include_error, true) != false,
      include_duration: Keyword.get(opts, :include_duration, true) != false
    }

    detach()
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, config)
  end

  @doc "Detaches the telemetry handler."
  @spec detach() :: :ok
  def detach do
    _ = :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  def handle_event(event, measurements, meta, config) do
    # Telemetry permanently detaches a handler that raises, which would silently stop every
    # report, so nothing here may raise.
    try do
      with %{job: %{worker: worker} = job} <- meta,
           {:ok, {base, token}} <- Map.fetch(config.workers, worker) do
        case action(event, meta, job, config) do
          :success ->
            HawkEye.ping(url(base, token), message: success_message(measurements, config))

          :fail ->
            HawkEye.fail(url(base, token), message: failure_message(event, meta, job, config))

          :ignore ->
            :ok
        end
      end
    rescue
      error ->
        Logger.error("[hawk_eye] could not report an Oban job: " <> Exception.message(error))
    catch
      kind, reason ->
        Logger.error(
          "[hawk_eye] could not report an Oban job: " <> Exception.format_banner(kind, reason)
        )
    end

    :ok
  end

  defp action([:oban, :job, :stop], %{state: state}, _job, config) do
    case state do
      :success -> :success
      :discard -> :fail
      :cancelled -> config.cancelled
      _ -> :ignore
    end
  end

  defp action([:oban, :job, :exception], meta, job, config) do
    final? = Map.get(meta, :state) == :discard or final_attempt?(job)
    if final? or config.fail_on == :every_attempt, do: :fail, else: :ignore
  end

  defp action(_event, _meta, _job, _config), do: :ignore

  defp final_attempt?(%{attempt: attempt, max_attempts: max})
       when is_integer(attempt) and is_integer(max),
       do: attempt >= max

  defp final_attempt?(_job), do: false

  defp success_message(%{duration: duration}, %{include_duration: true})
       when is_integer(duration) do
    "completed in #{System.convert_time_unit(duration, :native, :millisecond)} ms"
  end

  defp success_message(_measurements, _config), do: nil

  defp failure_message(event, meta, job, config) do
    summary =
      "#{job.worker} #{outcome(event, meta)} on attempt #{job.attempt} of #{job.max_attempts}"

    case config.include_error && error_text(meta) do
      text when is_binary(text) and text != "" -> summary <> ": " <> text
      _ -> summary
    end
  end

  defp outcome([:oban, :job, :stop], %{state: :discard}), do: "was discarded"
  defp outcome([:oban, :job, :stop], %{state: :cancelled}), do: "was canceled"
  defp outcome(_event, _meta), do: "failed"

  defp error_text(%{kind: kind, reason: reason}) when not is_nil(reason),
    do: Exception.format_banner(kind, reason)

  defp error_text(%{result: {tag, reason}}) when tag in [:discard, :cancel], do: inspect(reason)
  defp error_text(_meta), do: nil

  defp url(nil, token), do: token
  defp url(base, token), do: base <> "/ping/" <> token

  defp normalize_workers(workers) when is_map(workers) or is_list(workers) do
    Enum.reduce(workers, %{}, fn {worker, value}, acc ->
      name = worker_name(worker)

      case Token.parse(value) do
        {:ok, base, token} ->
          Map.put(acc, name, {base, token})

        :error ->
          problem =
            if is_nil(value),
              do: "no ping token",
              else: "an invalid ping token #{Token.redact(value)}"

          Logger.warning("[hawk_eye] not reporting #{name} to HawkEye: it has #{problem}")
          acc
      end
    end)
  end

  defp normalize_workers(_),
    do: raise(ArgumentError, ":workers must be a map of worker module to ping token")

  defp worker_name(worker) when is_atom(worker), do: inspect(worker)
  defp worker_name("Elixir." <> name), do: name
  defp worker_name(worker) when is_binary(worker), do: worker

  defp option(opts, key, allowed) do
    value = Keyword.get(opts, key, hd(allowed))

    if value in allowed do
      value
    else
      raise ArgumentError,
            "#{inspect(key)} must be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end
end
