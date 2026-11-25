defmodule HawkEye.HTTP.HttpcTest do
  # Sends a real request through :httpc to a one-shot local server.
  use ExUnit.Case, async: true

  test "posts the body and headers and returns the status" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      send(parent, {:request, read_request(socket, "")})
      :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nOK")
      :gen_tcp.close(socket)
    end)

    assert HawkEye.HTTP.Httpc.post(
             "http://127.0.0.1:#{port}/ping/Xr2kQ9vLmP4sT7wYbN3c5A/fail",
             [{"user-agent", "hawk_eye/test"}],
             "boom",
             timeout: 5_000
           ) == {:ok, 200}

    assert_receive {:request, request}
    assert request =~ "POST /ping/Xr2kQ9vLmP4sT7wYbN3c5A/fail HTTP/1.1"
    assert request =~ ~r/user-agent: hawk_eye\/test/i
    assert request =~ ~r/content-type: text\/plain; charset=utf-8/i
    assert String.ends_with?(request, "\r\n\r\nboom")
  end

  test "returns a transport error when nothing is listening" do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)

    assert {:error, _} =
             HawkEye.HTTP.Httpc.post("http://127.0.0.1:#{port}/ping/x", [], "", timeout: 2_000)
  end

  defp read_request(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    acc = acc <> data

    case String.split(acc, "\r\n\r\n", parts: 2) do
      [head, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, head)
        if byte_size(body) >= String.to_integer(length), do: acc, else: read_request(socket, acc)

      _ ->
        read_request(socket, acc)
    end
  end
end
