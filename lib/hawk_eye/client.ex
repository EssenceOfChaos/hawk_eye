defmodule HawkEye.Client do
  @moduledoc false

  alias HawkEye.Token

  require Logger

  @default_base_url "https://hawkeye.observer"
  @default_timeout 10_000
  # Waits before the second and third attempts. A lost success ping would turn into a false
  # "missed run" alert later, so transient errors are worth retrying.
  @default_retry_delays [1_000, 5_000]
  # HawkEye keeps the first 1,000 characters of a ping's body.
  @max_message 1_000
  @version Mix.Project.config()[:version]

  @spec post(String.t() | nil, String.t(), String.t(), String.t() | nil) :: :ok | {:error, term()}
  def post(base_url, token, suffix, message) do
    url =
      String.trim_trailing(base_url || configured_base_url(), "/") <> "/ping/" <> token <> suffix

    headers = [{"user-agent", "hawk_eye/#{@version} (Elixir)"}]
    body = message |> to_string() |> String.slice(0, @max_message)

    attempt(url, headers, body, token, retry_delays())
  end

  defp attempt(url, headers, body, token, delays) do
    case http_client().post(url, headers, body, timeout: timeout()) do
      {:ok, status} when status in 200..299 ->
        :ok

      {:ok, 404} ->
        Logger.warning(
          "[hawk_eye] HawkEye doesn't recognize the heartbeat token #{Token.redact(token)}. " <>
            "Check that it was copied from the monitor and that the monitor still exists."
        )

        {:error, :unknown_token}

      {:ok, status} when status == 429 or status >= 500 ->
        retry_or_give_up(url, headers, body, token, delays, {:http_status, status})

      {:ok, status} ->
        log_failure(token, {:http_status, status})
        {:error, {:http_status, status}}

      {:error, reason} ->
        retry_or_give_up(url, headers, body, token, delays, reason)
    end
  end

  defp retry_or_give_up(url, headers, body, token, [delay | rest], _reason) do
    Process.sleep(delay)
    attempt(url, headers, body, token, rest)
  end

  defp retry_or_give_up(_url, _headers, _body, token, [], reason) do
    log_failure(token, reason)
    {:error, reason}
  end

  defp log_failure(token, reason) do
    Logger.warning(
      "[hawk_eye] could not send a ping for #{Token.redact(token)}: #{inspect(reason)}"
    )
  end

  defp configured_base_url, do: Application.get_env(:hawk_eye, :base_url, @default_base_url)
  defp timeout, do: Application.get_env(:hawk_eye, :timeout, @default_timeout)
  defp retry_delays, do: Application.get_env(:hawk_eye, :retry_delays, @default_retry_delays)
  defp http_client, do: Application.get_env(:hawk_eye, :http_client, HawkEye.HTTP.Httpc)
end
