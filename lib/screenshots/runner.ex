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
    send self(), :start
    {:ok, %{pages: ScreenshotsWeb.PageController.pages(), tasks: []}}
  end

  def start_page({name, path}) do
    case Enum.reduce([:ref, :test], :ok, &check_url(&1, &2, path)) do
      :ok -> do_start_page(name, path)
      error -> Task.async(fn -> error end)
    end
  end

  defp do_start_page(name, path) do
    Task.async(__MODULE__, :take_screenshots, [name, path])
  end

  def handle_info(:start, %{tasks: [], pages: pages} = state) do
    IO.inspect "starting Screenshots.Runner"
    {:ok, _} = setup()
    {:noreply, %{state | tasks: Enum.map(pages, &start_page/1)}}
  end
  def handle_info(:start, state) do
    IO.inspect(state, label: "unfinished Screenshots.Runner tasks")
    with {name, _path} <- state.pages,
         {breakpoint, _dimensions} <- @breakpoints,
         type <- [:ref, :test]
    do send_screenshot(name, type, breakpoint) end
    {:noreply, state}
  end
  def handle_info({ref, :ok}, state) when is_reference(ref) do
    {:noreply, state}
  end
  def handle_info({ref, {:error, %{error: %{message: "There was an uncaught javascript error"}}} = error}, state) when is_reference(ref) do
    IO.inspect {:error, error}, label: "task error"
    {:noreply, state}
  end
  def handle_info({ref, {:error, error}}, state) when is_reference(ref) do
    IO.inspect {:error, error}, label: "task error"
    Enum.map(state.tasks, &Task.shutdown/1)
    Application.stop(:wallaby)
    {:noreply, state}
  end
  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    {:noreply, %{state | tasks: drop_task(state.tasks, ref, [])}}
  end

  defp check_url(type, :ok, path) do
    type
    |> build_url(path)
    |> HTTPoison.get()
    |> do_check_url()
  end
  defp check_url(_, error, _), do: error

  defp do_check_url({:error, error}), do: {:error, error}
  defp do_check_url({:ok, %HTTPoison.Response{status_code: 500} = response}), do: {:error, response}
  defp do_check_url({:ok, _}), do: :ok

  def take_screenshots(name, path) do
    case take_screenshot(name, path, :ref) do
      :ok -> take_screenshot(name, path, :test)
      error -> error
    end
  end

  defp drop_task([], _ref, acc), do: acc
  defp drop_task([%Task{ref: ref}], ref, acc), do: acc
  defp drop_task([%Task{ref: ref} | rest], ref, acc), do: rest ++ acc
  defp drop_task([%Task{} = task | rest], ref, acc), do: drop_task(rest, ref, [task | acc])

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
  end

  defp take_screenshot(name, path, type) do
    {:ok, session} = Wallaby.start_session()
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, name, build_url(type, path), type])
    |> Task.yield(30_000)
    |> do_take_screenshot(name, type, path)
  end

  defp base_url(:ref), do: "https://dev.mbtace.com"
  defp base_url(:test), do: "http://localhost:4001"

  defp build_url(type, path) do
    type
    |> base_url()
    |> Path.join(path)
  end

  def ensure_page_loaded(session, name, "http" <> _ = url, type) do
    session = Browser.visit(session, url)
    if Browser.has?(session, Query.css("main")) do
      session
    else
      ensure_page_loaded(session, name, url, type)
    end
  end

  defp do_take_screenshot(nil, name, type, path) do
    handle_error(name, path, type, :timeout)
  end
  defp do_take_screenshot({:ok, %Wallaby.Session{} = session}, name, type, _path) do
    Application.put_env(:wallaby, :screenshot_dir, screenshot_dir(type))
    for {breakpoint, {width, height}} <- @breakpoints do
      session
      |> Browser.resize_window(width, height)
      |> Browser.take_screenshot(name: file_name(name, breakpoint, false))
      send_screenshot(name, breakpoint, type)
    end
    Wallaby.end_session(session)
  end

  defp file_name(name, breakpoint, add_ext? \\ true)
  defp file_name(name, breakpoint, false), do: IO.iodata_to_binary([name,"_", Atom.to_string(breakpoint)])
  defp file_name(name, breakpoint, true), do: IO.iodata_to_binary([file_name(name, breakpoint, false), ".png"])

  defp send_screenshot(name, breakpoint, type) do
    name
    |> file_name(breakpoint)
    |> curry(Path, :join, [screenshot_dir(type)])
    |> File.stat()
    |> do_send_screenshot(name, breakpoint, type)
  end

  def curry(last_arg, module, func, args)
  when is_atom(module)
  and is_atom(func)
  and is_list(args), do: apply(module, func, Enum.concat(args, [last_arg]))

  defp do_send_screenshot({:ok, _}, name, breakpoint, type) do
    ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "#{type}_image", %{page_name: name, name: file_name(name, breakpoint, false), breakpoint: breakpoint}
  end

  defp handle_error(name, path, type, error) do
    info = %{name: name, path: path, type: type, error: error}
    ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "error", info
    {:error, info}
  end

  defp screenshot_dir(type) do
    Path.join([@screenshot_dir, Atom.to_string(type)])
  end
end
