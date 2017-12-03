defmodule ScreenshotsWeb.PageController do
  use ScreenshotsWeb, :controller

  @breakpoints %{
    xs_narrow: {320, 480},
    xs_wide: {543, 713},
    sm_narrow: {544, 714},
    sm_wide: {799, 1023},
    md_lg: {800, 1024},
    xxl: {1236, 1600}
  }

  def pages do
    case System.get_env("SCREENSHOT_PATH") do
      nil ->
        :screenshots
        |> Application.app_dir("priv")
        |> Path.join("pages.json")
        |> File.read!()
        |> Poison.decode!()
      path ->
        name = System.get_env("SCREENSHOT_NAME") || default_name(path)
        %{name => path}
    end
  end

  def index(conn, _params) do
    render conn, "index.html", pages: pages(), breakpoints: @breakpoints
  end

  defp default_name(path) do
    path
    |> String.replace("/", "__")
    |> String.replace("?", "__")
    |> String.replace("=", "-")
  end
end
