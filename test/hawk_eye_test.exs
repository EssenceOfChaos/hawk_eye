defmodule HawkEyeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @token "Xr2kQ9vLmP4sT7wYbN3c5A"

  setup do
    Application.put_env(:hawk_eye, :test_pid, self())
    HawkEye.TestHTTP.queue([])
    on_exit(fn -> Application.delete_env(:hawk_eye, :enabled) end)
  end

  describe "ping/2, fail/2 and exit_status/3" do
    test "post to the ping address on hawkeye.observer" do
      assert HawkEye.ping(@token, async: false) == :ok
      assert_received {:ping, "https://hawkeye.observer/ping/" <> @token, headers, "", _}
      assert {"user-agent", "hawk_eye/" <> _} = List.keyfind(headers, "user-agent", 0)

      assert HawkEye.fail(@token, message: "boom", async: false) == :ok
      assert_received {:ping, "https://hawkeye.observer/ping/" <> @token <> "/fail", _, "boom", _}

      assert HawkEye.exit_status(@token, 3, async: false) == :ok
      assert_received {:ping, "https://hawkeye.observer/ping/" <> @token <> "/3", _, "", _}
    end

    test "send in the background by default" do
      assert HawkEye.ping(@token) == :ok
      assert_receive {:ping, "https://hawkeye.observer/ping/" <> @token, _, _, _}
    end

    test "accept a whole ping URL and send to its host" do
      url = "https://status.example.com:8443/ping/#{@token}/fail"
      assert HawkEye.ping(url, async: false) == :ok
      assert_received {:ping, "https://status.example.com:8443/ping/" <> @token, _, _, _}
    end

    test "keep the first 1,000 characters of a message" do
      HawkEye.fail(@token, message: String.duplicate("é", 1_500), async: false)
      assert_received {:ping, _, _, body, _}
      assert String.length(body) == 1_000
    end

    test "refuse an invalid or missing token without sending anything" do
      log =
        capture_log(fn ->
          assert HawkEye.ping("not-a-token", async: false) == {:error, :invalid_token}
          assert HawkEye.ping(nil, async: false) == {:error, :invalid_token}
        end)

      assert log =~ "invalid token"
      refute_received {:ping, _, _, _, _}
    end

    test "do nothing when disabled" do
      Application.put_env(:hawk_eye, :enabled, false)
      assert HawkEye.ping(@token, async: false) == :ok
      refute_received {:ping, _, _, _, _}
    end

    test "retry server errors and rate limits, then succeed" do
      HawkEye.TestHTTP.queue([{:ok, 503}, {:error, :timeout}, {:ok, 200}])
      assert HawkEye.ping(@token, async: false) == :ok
      for _ <- 1..3, do: assert_received({:ping, _, _, _, _})
    end

    test "give up after three attempts and log without the full token" do
      HawkEye.TestHTTP.queue([{:ok, 429}, {:ok, 502}, {:error, :econnrefused}])

      log =
        capture_log(fn ->
          assert HawkEye.ping(@token, async: false) == {:error, :econnrefused}
        end)

      assert log =~ "Xr2k…"
      refute log =~ @token
    end

    test "don't retry an unknown token" do
      HawkEye.TestHTTP.queue([{:ok, 404}])

      log =
        capture_log(fn ->
          assert HawkEye.ping(@token, async: false) == {:error, :unknown_token}
        end)

      assert log =~ "doesn't recognize"
      assert_received {:ping, _, _, _, _}
      refute_received {:ping, _, _, _, _}
    end
  end

  describe "track/3" do
    test "report success and return the function's value" do
      assert HawkEye.track(@token, fn -> {:ok, 42} end, async: false) == {:ok, 42}
      assert_received {:ping, "https://hawkeye.observer/ping/" <> @token, _, "", _}
    end

    test "report a failure and reraise" do
      assert_raise RuntimeError, "boom", fn ->
        HawkEye.track(@token, fn -> raise "boom" end, async: false)
      end

      assert_received {:ping, "https://hawkeye.observer/ping/" <> @token <> "/fail", _, body, _}
      assert body =~ "(RuntimeError) boom"
    end

    test "report a throw or exit too" do
      assert catch_throw(HawkEye.track(@token, fn -> throw(:stop) end, async: false)) == :stop
      assert_received {:ping, _, _, "** (throw) :stop", _}

      assert catch_exit(HawkEye.track(@token, fn -> exit(:shutdown) end, async: false)) ==
               :shutdown

      assert_received {:ping, _, _, "** (exit) shutdown", _}
    end
  end
end
