defmodule ScreenshotsWeb.PageController do
  use ScreenshotsWeb, :controller

  @pages %{
    "Wollaston" => "/projects/wollaston-station-improvements",
    "Projects" => "/projects",
    "Fares" => "/fares"
  }

  def index(conn, _params) do
    render conn, "index.html", pages: @pages
  end
end
