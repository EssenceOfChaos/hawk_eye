defmodule HawkEye.ObanTest do
  # These events have the shape Oban 2.24 emits (lib/oban/queues/executor.ex, emit_event/1).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @token "Xr2kQ9vLmP4sT7wYbN3c5A"
  @other "Bq7mW2xZ9pK4nT6vR8sL1A"
  @url "https://hawkeye.observer/ping/"

  setup do
    Application.put_env(:hawk_eye, :test_pid, self())
    HawkEye.TestHTTP.queue([])

    :ok =
      HawkEye.Oban.attach(workers: %{MyApp.Nightly => @token, "Elixir.MyApp.Hourly" => @other})

    on_exit(&HawkEye.Oban.detach/0)
  end

  defp job(worker \\ "MyApp.Nightly", attempt \\ 1, max \\ 3),
    do: %{worker: worker, attempt: attempt, max_attempts: max, args: %{"secret" => "x"}}

  defp stop(state, extra \\ %{}, job \\ job()) do
    meta = Map.merge(%{job: job, state: state, result: :ok, conf: nil}, extra)

    :telemetry.execute(
      [:oban, :job, :stop],
      %{duration: System.convert_time_unit(1_250, :millisecond, :native)},
      meta
    )
  end

  defp exception(state, job, extra \\ %{}) do
    reason = RuntimeError.exception("database timeout")

    meta =
      Map.merge(
        %{job: job, state: state, kind: :error, reason: reason, error: reason, stacktrace: []},
        extra
      )

    :telemetry.execute([:oban, :job, :exception], %{duration: 1}, meta)
  end

  test "a successful job pings with its duration" do
    stop(:success)
    assert_receive {:ping, @url <> @token, _, "completed in 1250 ms", _}
  end

  test "workers are matched by module or by name" do
    stop(:success, %{}, job("MyApp.Hourly"))
    assert_receive {:ping, @url <> @other, _, _, _}
  end

  test "workers that aren't configured are ignored" do
    stop(:success, %{}, job("MyApp.Other"))
    exception(:discard, job("MyApp.Other", 3, 3))
    refute_receive {:ping, _, _, _, _}, 100
  end

  test "a failure that will be retried isn't reported" do
    exception(:failure, job("MyApp.Nightly", 1, 3))
    refute_receive {:ping, _, _, _, _}, 100
  end

  test "a failure on the last attempt is reported with the error" do
    exception(:discard, job("MyApp.Nightly", 3, 3))
    assert_receive {:ping, @url <> @token <> "/fail", _, body, _}
    assert body == "MyApp.Nightly failed on attempt 3 of 3: ** (RuntimeError) database timeout"
    refute body =~ "secret"
  end

  test "the last attempt is recognized without a state, as in older Oban versions" do
    exception(nil, job("MyApp.Nightly", 3, 3), %{state: nil})
    assert_receive {:ping, @url <> @token <> "/fail", _, _, _}
  end

  test "a job the worker discards is reported as a failure" do
    stop(:discard, %{result: {:discard, :bad_input}})

    assert_receive {:ping, @url <> @token <> "/fail", _,
                    "MyApp.Nightly was discarded on attempt 1 of 3: :bad_input", _}
  end

  test "snoozed and canceled jobs aren't reported by default" do
    stop(:snoozed, %{result: {:snooze, 60}})
    stop(:cancelled, %{result: {:cancel, :nothing_to_do}})
    refute_receive {:ping, _, _, _, _}, 100
  end

  test "fail_on: :every_attempt reports every failed attempt" do
    :ok = HawkEye.Oban.attach(workers: %{MyApp.Nightly => @token}, fail_on: :every_attempt)
    exception(:failure, job("MyApp.Nightly", 1, 3))
    assert_receive {:ping, @url <> @token <> "/fail", _, _, _}
  end

  test "cancelled: chooses what a canceled job reports" do
    :ok = HawkEye.Oban.attach(workers: %{MyApp.Nightly => @token}, cancelled: :success)
    stop(:cancelled, %{result: {:cancel, :nothing_to_do}})
    assert_receive {:ping, @url <> @token, _, _, _}

    :ok = HawkEye.Oban.attach(workers: %{MyApp.Nightly => @token}, cancelled: :fail)
    stop(:cancelled, %{result: {:cancel, :nothing_to_do}})

    assert_receive {:ping, @url <> @token <> "/fail", _,
                    "MyApp.Nightly was canceled on attempt 1 of 3: :nothing_to_do", _}
  end

  test "include_error: false leaves the error text out" do
    :ok =
      HawkEye.Oban.attach(
        workers: %{MyApp.Nightly => @token},
        include_error: false,
        include_duration: false
      )

    exception(:discard, job("MyApp.Nightly", 3, 3))
    assert_receive {:ping, _, _, "MyApp.Nightly failed on attempt 3 of 3", _}

    stop(:success)
    assert_receive {:ping, @url <> @token, _, "", _}
  end

  test "a whole ping URL can be configured" do
    :ok =
      HawkEye.Oban.attach(
        workers: %{MyApp.Nightly => "https://hawkeye.example.org/ping/#{@token}"}
      )

    stop(:success)
    assert_receive {:ping, "https://hawkeye.example.org/ping/" <> @token, _, _, _}
  end

  test "a worker without a token is skipped with a warning, not a crash" do
    log =
      capture_log(fn ->
        assert :ok = HawkEye.Oban.attach(workers: %{MyApp.Nightly => nil, MyApp.Hourly => "nope"})
      end)

    assert log =~ "not reporting MyApp.Nightly to HawkEye: it has no ping token"
    assert log =~ "not reporting MyApp.Hourly to HawkEye: it has an invalid ping token"

    stop(:success)
    refute_receive {:ping, _, _, _, _}, 100
  end

  test "invalid options are rejected" do
    assert_raise ArgumentError, ~r/:fail_on must be one of/, fn ->
      HawkEye.Oban.attach(workers: %{}, fail_on: :sometimes)
    end
  end

  test "the handler stays attached after an unexpected event" do
    capture_log(fn ->
      :telemetry.execute([:oban, :job, :stop], %{}, %{job: %{worker: "MyApp.Nightly"}})
    end)

    stop(:success)
    assert_receive {:ping, @url <> @token, _, _, _}
  end
end
