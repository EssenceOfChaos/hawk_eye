defmodule HawkEye.TestHTTP do
  @moduledoc false
  @behaviour HawkEye.HTTP

  # Sends each request to the test process and answers with the queued responses (default 200).

  @impl true
  def post(url, headers, body, opts) do
    test_pid = Application.fetch_env!(:hawk_eye, :test_pid)
    send(test_pid, {:ping, url, headers, body, opts})

    Agent.get_and_update(HawkEye.TestHTTP.Responses, fn
      [next | rest] -> {next, rest}
      [] -> {{:ok, 200}, []}
    end)
  end

  def queue(responses), do: Agent.update(HawkEye.TestHTTP.Responses, fn _ -> responses end)
end

{:ok, _} = Agent.start(fn -> [] end, name: HawkEye.TestHTTP.Responses)

Application.put_env(:hawk_eye, :http_client, HawkEye.TestHTTP)
Application.put_env(:hawk_eye, :retry_delays, [0, 0])

ExUnit.start()
