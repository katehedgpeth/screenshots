defmodule Screenshots.Runner do
  use GenServer
  alias Wallaby.{Browser, Query}

  @screenshot_dir Application.app_dir(:screenshots, "priv/screenshots")
  @breakpoints %{
    xs_narrow: {320, 480},
    xs_wide: {543, 713},
    sm_narrow: {544, 714},
    sm_wide: {799, 1023},
    md_lg: {800, 1024},
    xxl: {1236, 1600}
  }

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, %{status: :idle, pages: ScreenshotsWeb.PageController.pages(), session: nil}}
  end

  def handle_cast(:start, %{status: :idle, pages: pages} = state) do
    IO.inspect "starting up Screenshots.Runner"
    {:ok, session} = setup()
    pages
    |> Enum.with_index()
    |> Enum.map(&start_page/1)
    {:noreply, %{state | status: :running, session: session}}
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
    Process.send_after self(), {:start_page, {name, path}}, 2_000
    {:noreply, state}
  end
  def handle_info({:start_page, {name, path}}, %{status: {:error, error}, session: %Wallaby.Session{} = session} = state) do
    IO.inspect {{name, path}, error}, label: "shutting down Wallaby due to error"
    :ok = Wallaby.end_session(session)
    {:noreply, %{state | session: nil}}
  end
  def handle_info({:start_page, {name, path}}, %{session: %Wallaby.Session{}} = state) do
    send self(), {:take_screenshot, {name, path, :ref}}
    {:noreply, Map.put(state, :current_page, {name, path})}
  end
  def handle_info({:start_page, _}, state) do
    {:noreply, %{state | status: :idle}}
  end
  def handle_info({:take_screenshot, {name, path, type}}, state) do
    case {take_screenshot(state.session, name, path, type), type} do
      {{:ok, %Wallaby.Session{}}, :ref} ->
        send self(), {:take_screenshot, {name, path, :test}}
      {{:ok, %Wallaby.Session{}}, :test} ->
        send self(), {:page_finished, name, :ok}
      {{:error, error}, _} ->
        send self(), {:page_finished, name, {:error, error}}
    end
    {:noreply, state}
  end
  def handle_info({:page_finished, page_name, result}, state) do
    {:noreply, state
               |> Map.delete(:current_page)
               |> Map.put(:pages, Map.delete(state.pages, page_name))
               |> update_state(result)}
  end

  defp update_state(%{session: %Wallaby.Session{}} = state, result) do
    case {result, state.pages |> Map.keys() |> length} do
      {:ok, 0} ->
        :ok = Wallaby.end_session(state.session)
        Application.stop(:wallaby)
        %{state | status: :idle, session: nil}
      {:ok, _} -> state
      {{:error, %{error: %{message: "There was an uncaught javascript error" <> _}}}, 0} ->
        :ok = Wallaby.end_session(state.session)
        Application.stop(:wallaby)
        %{state | status: :idle, session: nil}
      {{:error, %{error: %{message: "There was an uncaught javascript error" <> _}}}, _} -> state
      {{:error, error}, _} ->
        :ok = Wallaby.end_session(state.session)
        Application.stop(:wallaby)
        %{state | status: {:error, error}, session: nil}
    end
  end

  defp setup do
    File.rm_rf!(@screenshot_dir)
    File.mkdir_p!(Path.join([@screenshot_dir, "test"]))
    File.mkdir_p!(Path.join([@screenshot_dir, "ref"]))
    {:ok, _} = Application.ensure_all_started(:wallaby)
    {:ok, %Wallaby.Session{}} = Wallaby.start_session()
  end

  defp take_screenshot(%Wallaby.Session{} = session, name, path, type) do
    url = type
          |> base_url()
          |> Path.join(path)
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, name, url, type])
    |> Task.await(30_000)
    |> do_take_screenshot(name, type, path)
  rescue
    error ->
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
    for {breakpoint, {width, height}} <- @breakpoints do
      file_name = "#{name}_#{breakpoint}"
      session
      |> Browser.resize_window(width, height)
      |> Browser.take_screenshot(name: file_name)
      ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "#{type}_image", %{page_name: name, name: file_name, breakpoint: breakpoint}
    end
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
