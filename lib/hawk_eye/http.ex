defmodule HawkEye.HTTP do
  @moduledoc false

  # Sends a ping. The body is plain text. Returns the response status or a transport error.
  @callback post(
              url :: String.t(),
              headers :: [{String.t(), String.t()}],
              body :: binary(),
              opts :: keyword()
            ) ::
              {:ok, non_neg_integer()} | {:error, term()}
end

defmodule HawkEye.HTTP.Httpc do
  @moduledoc false
  @behaviour HawkEye.HTTP

  # Erlang's built-in client, so the package adds no HTTP dependency to your application.

  @impl true
  def post(url, headers, body, opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
    request = {String.to_charlist(url), headers, ~c"text/plain; charset=utf-8", body}

    http_opts = [
      timeout: timeout,
      connect_timeout: min(timeout, 5_000),
      autoredirect: false,
      ssl: ssl_opts()
    ]

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, _body}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end
end
