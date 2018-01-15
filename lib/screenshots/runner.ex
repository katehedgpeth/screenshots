defmodule Screenshots.Runner do
  use GenServer
  alias Wallaby.{Browser, Query, Session}

  defstruct [:current_task, not_run: []]

  @screenshot_dir Application.app_dir(:screenshots, "priv/screenshots")
  @breakpoints [
    xs_narrow: {320, 480},
    xs_wide: {543, 713},
    sm_narrow: {544, 714},
    sm_wide: {799, 1023},
    md_lg: {800, 1024},
    xxl: {1236, 1600}
  ]

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    send self(), :start
    {:ok, %__MODULE__{}}
  end

  def handle_call(:pages, _from, state) do
    {:reply, read_json(), state}
  end
  def handle_call(:breakpoints, _from, state) do
    {:reply, @breakpoints, state}
  end

  def handle_info(:start, %__MODULE__{not_run: [], current_task: nil} = state) do
    IO.inspect "starting Screenshots.Runner"
    {:ok, _} = setup()
    send self(), :start_page
    {:noreply, %{state | not_run: read_json()}}
  end
  def handle_info(:start, %__MODULE__{} = state) do
    with {name, _path} <- read_json(),
         {breakpoint, _dimensions} <- @breakpoints,
         type <- [:ref, :test]
    do send_screenshot(name, type, breakpoint) end
    {:noreply, state}
  end
  def handle_info(:start_page, %__MODULE__{not_run: [{name, path} | not_run], current_task: :nil} = state) do
    {:noreply, %{state | not_run: not_run,
                         current_task: Task.async(__MODULE__, :start_page, [name, path])}}
  end
  def handle_info(:start_page, %__MODULE__{} = state) do
    send self(), :start_page
    {:noreply, state}
  end
  def handle_info({ref, :ok}, %__MODULE__{} = state) when is_reference(ref) do
    {:noreply, state}
  end
  def handle_info({ref, {:error, %{error: %Wallaby.JSError{}} = error}}, %__MODULE__{} = state) when is_reference(ref) do
    IO.inspect {:error, error}, label: "task error"
    {:noreply, state}
  end
  def handle_info({ref, {:error, error}}, %__MODULE__{current_task: %Task{} = task} = state) when is_reference(ref) do
    IO.inspect {:error, error}, label: "task error"
    Task.shutdown(task)
    Application.stop(:wallaby)
    {:noreply, %{state | current_task: nil}}
  end
  def handle_info({ref, {:error, error}}, %__MODULE__{current_task: nil} = state) when is_reference(ref) do
    Application.stop(:wallaby)
    {:noreply, state}
  end
  def handle_info({:DOWN, ref, :process, _pid, :normal}, %__MODULE__{current_task: %Task{ref: ref}} = state) do
    case state.not_run do
      [] -> Application.stop(:wallaby)
      _ -> send self(), :start_page
    end
    {:noreply, %{state | current_task: nil}}
  end

  defp read_json do
    :screenshots
    |> Application.app_dir("priv")
    |> Path.join("pages.json")
    |> File.read!()
    |> Poison.decode!(keys: :atoms)
    |> Enum.into([])
  end

  def start_page(name, %{} = opts) do
    case Enum.reduce([:ref, :test], :ok, &check_url(&1, &2, opts)) do
      :ok -> take_screenshots(name, opts)
      error -> error
    end
  end

  defp check_url(type, :ok, %{} = opts) do
    type
    |> build_url(opts)
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

  defp update_state(%{session: %Session{}} = state, result) do
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

  defp take_screenshot(name, %{} = opts, type) do
    {:ok, session} = Wallaby.start_session()
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, name, opts, type])
    |> Task.yield(30_000)
    |> do_take_screenshot(name, type, opts)
  end

  defp base_url(:ref), do: "https://dev.mbtace.com"
  defp base_url(:test), do: "http://localhost:4001"

  defp build_url(type, %{path: path}) do
    type
    |> base_url()
    |> Path.join(path)
  end

  def ensure_page_loaded(%Session{} = session, name, %{} = opts, type) do
    type
    |> build_url(opts)
    |> curry(Browser, :visit, [session])
    |> Browser.has?(Query.css("main"))
    |> do_ensure_page_loaded(session, name, opts, type)
  rescue
    error in Wallaby.JSError ->
      Wallaby.end_session(session)
      {:error, error}
  end

  defp do_ensure_page_loaded(true, %Session{} = session, _name, opts, _type) do
    hide_selectors(session, opts)
  end
  defp do_ensure_page_loaded(false, %Session{} = session, name, opts, type) do
    ensure_page_loaded(session, name, opts, type)
  end

  defp do_take_screenshot(nil, name, type, path) do
    handle_error(name, path, type, :timeout)
  end
  defp do_take_screenshot({:ok, {:error, error}}, name, type, path) do
    handle_error(name, path, type, error)
  end
  defp do_take_screenshot({:ok, %Session{} = session}, name, type, opts) do
    Application.put_env(:wallaby, :screenshot_dir, screenshot_dir(type))
    hide_selectors(session, opts)
    for {breakpoint, {width, height}} <- @breakpoints do
      session
      |> Browser.resize_window(width, height)
      |> Browser.take_screenshot(name: file_name(name, breakpoint, false))
      send_screenshot(name, breakpoint, type)
    end
    Wallaby.end_session(session)
  end

  defp hide_selectors(%Session{} = session, %{hide_selectors: selectors}) do
    Browser.execute_script(session, """
      function hideEl(el) { el.style.display = "none" }
      function hideSelector(selector) { document.querySelectorAll(selector).forEach(hideEl) }
      [#{Enum.join(selectors, ", ")}].forEach(hideSelector);
    """)
  end
  defp hide_selectors(%Session{} = session, _opts) do
    session
  end

  defp file_name(name, breakpoint, add_ext? \\ true)
  defp file_name(name, breakpoint, false) do
    [name, breakpoint]
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join("_")
    |> IO.iodata_to_binary()
  end
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
    for {breakpoint, _} <- @breakpoints do
      ScreenshotsWeb.Endpoint.broadcast "screenshots:test", "error", %{info | name: file_name(name, breakpoint, false)}
    end
    {:error, info}
  end

  defp screenshot_dir(type) do
    Path.join([@screenshot_dir, Atom.to_string(type)])
  end
end
