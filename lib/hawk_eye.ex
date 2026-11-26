defmodule HawkEye do
  @moduledoc """
  Report scheduled jobs to [HawkEye](https://hawkeye.observer/elixir?utm_medium=docs&utm_source=hawk_eye&utm_campaign=elixir) heartbeat monitors.

  HawkEye is the hosted service that watches the deadlines and sends the alerts, so you need
  an account: [create one free](https://hawkeye.observer/register?utm_medium=docs&utm_source=hawk_eye&utm_campaign=elixir) (no credit card; the
  Free plan includes 5 monitors).

  A heartbeat monitor expects a ping every period (for example once a day). When a ping is
  late, or the job reports a failure, HawkEye opens an incident and alerts you. HawkEye checks
  the deadline from outside your application, so it still alerts when your application,
  node or scheduler is down and nothing runs at all.

  For Oban workers, configure `HawkEye.Oban` and no code changes are needed. For anything
  else (Quantum jobs, GenServer timers, release tasks), call the functions in this module:

      HawkEye.track(System.get_env("HAWKEYE_NIGHTLY_REPORT"), fn ->
        MyApp.Reports.send_nightly()
      end)

  A token is the monitor's ping token, or its whole ping URL copied from HawkEye
  (`https://hawkeye.observer/ping/<token>`).

  ## Delivery

  Pings are sent in the background by default and never raise or block the caller: a
  failed request is retried twice, then logged. Pass `async: false` to wait for the result.

  ## Options

  * `:message` - text kept with the ping in HawkEye (for example the end of the job's
    output). HawkEye keeps the first 1,000 characters.
  * `:async` - `true` (default) to send in the background and return `:ok` at once;
    `false` to wait and return `:ok` or `{:error, reason}`.

  ## Configuration

      config :hawk_eye,
        enabled: true,                          # false turns every ping into a no-op
        base_url: "https://hawkeye.observer",   # where bare tokens are sent
        timeout: 10_000                         # milliseconds per attempt
  """

  alias HawkEye.{Client, Token}

  require Logger

  @typedoc "A ping token, or a whole ping URL."
  @type token :: String.t()
  @type result :: :ok | {:error, term()}

  @doc """
  Reports that the job ran successfully.
  """
  @spec ping(token(), keyword()) :: result()
  def ping(token, opts \\ []), do: deliver(token, "", opts)

  @doc """
  Reports that the job failed. HawkEye opens an incident straight away.

      HawkEye.fail(token, message: Exception.message(error))
  """
  @spec fail(token(), keyword()) :: result()
  def fail(token, opts \\ []), do: deliver(token, "/fail", opts)

  @doc """
  Reports the job's exit status: `0` is success, anything from `1` to `255` a failure.
  """
  @spec exit_status(token(), 0..255, keyword()) :: result()
  def exit_status(token, status, opts \\ []) when is_integer(status) and status in 0..255 do
    deliver(token, "/" <> Integer.to_string(status), opts)
  end

  @doc """
  Runs `fun`, then reports success, or failure if it raises, throws or exits.

  The error is reraised after the failure is reported, so your own error handling is
  unchanged. Returns what `fun` returns. A return value is never treated as a failure: call
  `fail/2` yourself if `{:error, _}` means the job failed.

  Accepts the options of `ping/2` except `:message`.
  """
  @spec track(token(), (-> value), keyword()) :: value when value: var
  def track(token, fun, opts \\ []) when is_function(fun, 0) do
    opts = Keyword.delete(opts, :message)

    try do
      fun.()
    catch
      kind, reason ->
        fail(
          token,
          Keyword.put(opts, :message, Exception.format_banner(kind, reason, __STACKTRACE__))
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      value ->
        ping(token, opts)
        value
    end
  end

  defp deliver(token, suffix, opts) do
    case Token.parse(token) do
      {:ok, base_url, token} ->
        if Application.get_env(:hawk_eye, :enabled, true) do
          send_ping(base_url, token, suffix, opts)
        else
          :ok
        end

      :error ->
        Logger.warning(
          "[hawk_eye] ignored a ping with an invalid token #{Token.redact(token)}: " <>
            "copy the ping URL or token from the heartbeat monitor in HawkEye"
        )

        {:error, :invalid_token}
    end
  end

  defp send_ping(base_url, token, suffix, opts) do
    message = Keyword.get(opts, :message)

    if Keyword.get(opts, :async, true) do
      try do
        {:ok, _pid} =
          Task.Supervisor.start_child(HawkEye.TaskSupervisor, fn ->
            Client.post(base_url, token, suffix, message)
          end)

        :ok
      catch
        :exit, _ ->
          Logger.warning(
            "[hawk_eye] could not send a ping: the :hawk_eye application isn't started"
          )

          {:error, :not_started}
      end
    else
      Client.post(base_url, token, suffix, message)
    end
  end
end
