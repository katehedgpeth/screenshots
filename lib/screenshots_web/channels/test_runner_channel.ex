defmodule ScreenshotsWeb.Channel do
  use ScreenshotsWeb, :channel
  alias Wallaby.{Browser, Query}

  @screenshot_dir Application.app_dir(:screenshots, "priv/screenshots")

  def join("screenshots:test", _payload, socket) do
    send self(), :start
    {:ok, socket}
  end

  def handle_info(:start, socket) do
    setup()
    Enum.map(ScreenshotsWeb.PageController.pages(), &take_screenshots(&1, socket))

    {:noreply, socket}
  end

  defp setup do
    File.rm_rf!(@screenshot_dir)
    File.mkdir_p!(Path.join([@screenshot_dir, "test"]))
    File.mkdir_p!(Path.join([@screenshot_dir, "ref"]))
    {:ok, _} = Application.ensure_all_started(:wallaby)
  end

  defp take_screenshots({name, opts}, socket) do
    {:ok, session} = Wallaby.start_session()
    session
    |> take_screenshot({name, opts}, :ref, socket)
    |> take_screenshot({name, opts}, :test, socket)
    |> Wallaby.end_session()
    {name, opts}
  end

  defp take_screenshot(session, {name, opts}, type, socket) do
    url = type
          |> base_url()
          |> Path.join(opts)
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, url])
    |> Task.await(10_000)
    |> do_take_screenshot(name, opts, type)
    push socket, "#{type}_image", %{name: name}
    session
  end

  defp base_url(:ref), do: "https://dev.mbtace.com"
  defp base_url(:test), do: "http://localhost:4001"

  def ensure_page_loaded(session, path) do
    session = Browser.visit(session, path)
    if Browser.has?(session, Query.css("main")) do
      session
    else
      ensure_page_loaded(session, path)
    end
  end

  defp do_take_screenshot(%Wallaby.Session{} = session, name, opts, type) do
    Application.put_env(:wallaby, :screenshot_dir, screenshot_dir(type))
    Browser.take_screenshot(session, name: name)
  end

  defp screenshot_dir(type) do
    Path.join([@screenshot_dir, Atom.to_string(type)])
  end
end
