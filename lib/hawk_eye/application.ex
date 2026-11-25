defmodule HawkEye.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [{Task.Supervisor, name: HawkEye.TaskSupervisor}]

    with {:ok, pid} <-
           Supervisor.start_link(children, strategy: :one_for_one, name: HawkEye.Supervisor) do
      if opts = Application.get_env(:hawk_eye, :oban), do: HawkEye.Oban.attach(opts)
      {:ok, pid}
    end
  end

  @impl true
  def stop(_state) do
    HawkEye.Oban.detach()
  end
end
