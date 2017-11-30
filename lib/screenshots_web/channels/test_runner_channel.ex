defmodule ScreenshotsWeb.Channel do
  use ScreenshotsWeb, :channel

  def join("screenshots:test", _payload, socket) do
    IO.inspect "casting to Screenshots.Runner"
    GenServer.cast(Screenshots.Runner, :start)
    {:ok, socket}
  end
end
