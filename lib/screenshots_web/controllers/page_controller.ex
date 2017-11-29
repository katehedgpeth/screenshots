defmodule ScreenshotsWeb.PageController do
  use ScreenshotsWeb, :controller

  @pages :screenshots
         |> Application.app_dir("priv")
         |> Path.join("pages.json")
         |> File.read!()
         |> Poison.decode!()

  def pages, do: @pages

  def index(conn, _params) do
    render conn, "index.html", pages: @pages
  end
end
