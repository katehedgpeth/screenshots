defmodule Screenshots.Runner do
  use GenServer
  alias Wallaby.{Browser, Query}

  @screenshot_dir Application.app_dir(:screenshots, "priv/screenshots")

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, %{status: :idle, pages: ScreenshotsWeb.PageController.pages()}}
  end

  def handle_cast(:start, %{status: :idle, pages: pages} = state) do
    IO.inspect "starting up Screenshots.Runner"
    setup()
    pages
    |> Enum.with_index()
    |> Enum.map(&start_page/1)
    {:noreply, %{state | status: :running}}
  end
  def handle_cast(:start, %{status: :running} = state) do
    IO.inspect state
    {:noreply, state}
  end
  def handle_cast(:start, state) do
    IO.inspect state
    {:noreply, state}
  end

  defp start_page({{name, path}, idx}) do
    Process.send_after self(), {:start_page, {name, path}}, idx * 2
    {name, path}
  end

  def handle_info({:start_page, {name, path}}, %{current_page: _} = state) do
    IO.inspect "not starting b/c page is running"
    Process.send_after self(), {:start_page, {name, path}}, 2_000
    {:noreply, state}
  end
  def handle_info({:start_page, {name, path}}, %{status: {:error, error}} = state) do
    IO.inspect {{name, path}, error}, label: "ignoring request to start page due to error"
    {:noreply, state}
  end
  def handle_info({:start_page, {name, path}}, state) do
    send self(), {:take_screenshots, {name, path}}
    {:noreply, Map.put(state, :current_page, {name, path})}
  end
  def handle_info({:take_screenshots, {name, path}}, state) do
    take_screenshots({name, path})
    {:noreply, state}
  end
  def handle_info({:page_finished, page_name, result}, state) do
    {:noreply, state
               |> Map.delete(:current_page)
               |> Map.put(:pages, Map.delete(state.pages, page_name))
               |> update_status(result)}
  end

  defp update_status(%{} = state, result) do
    case {result, state.pages |> Map.keys() |> length} do
      {:ok, 0} -> %{state | status: :idle}
      {:ok, _} -> state
      {{:error, %{error: %{message: "There was an uncaught javascript error" <> _}}}, 0} -> %{state | status: :idle}
      {{:error, %{error: %{message: "There was an uncaught javascript error" <> _}}}, _} -> state
      {{:error, error}, _} -> %{state | status: {:error, error}}
    end
  end

  defp setup do
    File.rm_rf!(@screenshot_dir)
    File.mkdir_p!(Path.join([@screenshot_dir, "test"]))
    File.mkdir_p!(Path.join([@screenshot_dir, "ref"]))
    {:ok, _} = Application.ensure_all_started(:wallaby)
  end

  defp take_screenshots({name, opts}) do
    IO.inspect {name, opts}, label: "starting screenshots for"
    case do_take_screenshots(name, opts) do
      {:ok, %Wallaby.Session{} = session} ->
        Wallaby.end_session(session)
        send self(), {:page_finished, name, :ok}
      {:error, error} ->
        send self(), {:page_finished, name, {:error, error}}
    end
  end

  defp do_take_screenshots(name, opts) do
    Wallaby.start_session()
    |> take_screenshot({name, opts}, :ref)
    |> take_screenshot({name, opts}, :test)
  end

  defp take_screenshot({:error, error}, _, _) do
    {:error, error}
  end
  defp take_screenshot({:ok, %Wallaby.Session{} = session}, {name, path}, type) do
    url = type
          |> base_url()
          |> Path.join(path)
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, name, url, type])
    |> Task.await(30_000)
    |> do_take_screenshot(name, type, path)
  rescue
    error ->
      Wallaby.end_session(session)
      {:error, %{name: name, path: path, type: type, error: error}}
  end

  defp base_url(:ref), do: "https://dev.mbtace.com"
  defp base_url(:test), do: "http://localhost:4001"

  def ensure_page_loaded(session, name, "http" <> _ = url, type) do
    session = Browser.visit(session, url)
    if Browser.has?(session, Query.css("main")) do
      session
    else
      ensure_page_loaded(session, name, url, type)
    end
  rescue
    error -> {:error, %{name: name, path: url, type: type, error: error}}
  end

  defp do_take_screenshot({:error, error}, _name, _type, _path) do
    ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "error", error
    {:error, error}
  end
  defp do_take_screenshot(%Wallaby.Session{} = session, name, type, path) do
    Application.put_env(:wallaby, :screenshot_dir, screenshot_dir(type))
    Browser.take_screenshot(session, name: name)
    ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "#{type}_image", %{name: name}
    {:ok, session}
  rescue
    error ->
      info = %{name: name, path: path, type: type, error: error}
      ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "error", info
      {:error, info}
  end

  defp screenshot_dir(type) do
    Path.join([@screenshot_dir, Atom.to_string(type)])
  end
end
