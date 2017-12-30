defmodule ScreenshotsWeb.Channel do
  use ScreenshotsWeb, :channel

  def join("screenshots:test", _payload, socket) do
    case GenServer.whereis(Screenshots.Runner) do
      nil ->
        {:error, %{error: "Screenshots.Runner not started"}}
      pid ->
        send pid, :start
        {:ok, socket}
    end
  end
end
