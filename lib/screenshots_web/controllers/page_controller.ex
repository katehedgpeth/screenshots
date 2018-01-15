defmodule ScreenshotsWeb.PageController do
  use ScreenshotsWeb, :controller

  @breakpoints [
    xs_narrow: {320, 480},
    xs_wide: {543, 713},
    sm_narrow: {544, 714},
    sm_wide: {799, 1023},
    md_lg: {800, 1024},
    xxl: {1236, 1600}
  ]

  def index(conn, _params) do
    case GenServer.whereis(Screenshots.Runner) do
      nil -> render conn, "error"
        _ -> render conn, "index.html"
    end
  end

  defp default_name(path) do
    path
    |> String.replace("/", "__")
    |> String.replace("?", "__")
    |> String.replace("=", "-")
  end
end
