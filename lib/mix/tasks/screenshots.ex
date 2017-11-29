defmodule Mix.Tasks.Screenshots do
  use Mix.Task
  # alias SiteWeb.{Endpoint, Router}
  alias Wallaby.{Browser, Query}

  @screenshot_dir Application.app_dir(:screenshots, "priv/screenshots")

  def run(_) do
    setup()

    :ok = pages()
    |> Enum.map(&take_screenshots/1)
    |> build_html()
    |> write_html_file()

    Mix.shell.cmd("open http://localhost:4001/screenshots/compare.html")
    :timer.sleep(5_000) # give a little time to ensure that the files get served before shutting down
  end

  defp setup do
    File.mkdir_p!(Path.join([@screenshot_dir, "test"]))
    File.mkdir_p!(Path.join([@screenshot_dir, "ref"]))
    {:ok, _} = Application.ensure_all_started(:wallaby)
    Task.async(fn -> Mix.Task.run("phx.server") end)
  end

  defp pages, do: %{
    "Wollaston" => "/projects/wollaston-station-improvements",
    "Projects" => "/projects",
    "Fares" => "/fares"
  }

  defp take_screenshots({name, opts}) do
    {:ok, session} = Wallaby.start_session()
    session
    |> take_screenshot({name, opts}, :ref)
    |> take_screenshot({name, opts}, :test)
    |> Wallaby.end_session()
    {name, opts}
  end

  defp take_screenshot(session, {name, opts}, type) do
    url = type
          |> base_url()
          |> Path.join(opts)
    __MODULE__
    |> Task.async(:ensure_page_loaded, [session, url])
    |> Task.await(10_000)
    |> do_take_screenshot(name, opts, type)
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

  defp build_html(screenshots) do
    """
    <html>
      <head>
        <style rel="text/css">
          .images {
            display: flex;
          }
          .image {
            flex: 1;
          }
        </style>
      </head>
      <body>
        #{screenshots |> Enum.map(&result_html/1) |> IO.iodata_to_binary()}
        <script type="text/javascript">#{javascript()}</script>
      </body>
    </html>
    """
  end

  defp result_html({name, path}) do
    """
    <div class="result">
      <h2>#{name}</h2>
      <p>#{path}</p>
      <div class="images">
        <div class="image image--test"><img src="http://localhost:4001/screenshots/test/#{name}.png" /></div>
        <div class="image image--ref"><img src="http://localhost:4001/screenshots/ref/#{name}.png" /></div>
        <div class="image image--diff"></div>
      </div>
    </div>
    """
  end

  defp javascript do
    {:ok, %HTTPoison.Response{body: resemble, status_code: 200}} = HTTPoison.get("https://raw.githubusercontent.com/Huddle/Resemble.js/master/resemble.js")
    resemble <> """
    Array.from(document.getElementsByClassName("result")).forEach(function(el) {
      var test_image = el.querySelector(".image--test img");
      var ref_image = el.querySelector(".image--ref img");
      resemble(ref_image.src).compareTo(test_image.src).onComplete(function(data) {
        var diff_image = new Image();
        diff_image.src = data.getImageDataUrl()
        el.querySelector(".image--diff").appendChild(diff_image);
      });
    });
    """
  end

  defp write_html_file(html) do
    @screenshot_dir
    |> Path.join("/compare.html")
    |> File.write(html)
  end
end
