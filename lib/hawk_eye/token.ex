defmodule HawkEye.Token do
  @moduledoc false

  # A ping token is 22 URL-safe base64 characters (128 random bits). It is the only secret in
  # a ping URL, so it is never logged in full.
  @token ~r/\A[A-Za-z0-9_-]{22}\z/

  @doc """
  Accepts a bare token or a whole ping URL (`https://host/ping/<token>`, optionally followed
  by `/fail` or an exit status, which are dropped). Returns the base URL to send to (`nil`
  for the configured one) and the token.
  """
  @spec parse(term()) :: {:ok, String.t() | nil, String.t()} | :error
  def parse(value) when is_binary(value) do
    value = String.trim(value)

    if String.starts_with?(value, ["https://", "http://"]) do
      parse_url(value)
    else
      if valid?(value), do: {:ok, nil, value}, else: :error
    end
  end

  def parse(_), do: :error

  defp parse_url(value) do
    uri = URI.parse(value)

    with true <- is_binary(uri.host) and uri.host != "",
         [_ | _] = segments <- String.split(uri.path || "", "/", trim: true),
         {:ok, token} <- token_after_ping(segments) do
      port = if uri.port in [nil, URI.default_port(uri.scheme)], do: "", else: ":#{uri.port}"
      {:ok, "#{uri.scheme}://#{uri.host}#{port}", token}
    else
      _ -> :error
    end
  end

  defp token_after_ping(["ping", token | _rest]),
    do: if(valid?(token), do: {:ok, token}, else: :error)

  defp token_after_ping([_ | rest]), do: token_after_ping(rest)
  defp token_after_ping([]), do: :error

  @spec valid?(term()) :: boolean()
  def valid?(token) when is_binary(token), do: Regex.match?(@token, token)
  def valid?(_), do: false

  @doc "The first four characters of a token, for log messages."
  @spec redact(term()) :: String.t()
  def redact(token) when is_binary(token) do
    case parse(token) do
      {:ok, _, token} -> String.slice(token, 0, 4) <> "…"
      :error -> "(unrecognized)"
    end
  end

  def redact(nil), do: "(missing)"
  def redact(_), do: "(unrecognized)"
end
