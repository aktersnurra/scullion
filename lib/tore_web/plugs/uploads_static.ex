defmodule ToreWeb.UploadsStatic do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(_opts) do
    dir = Application.fetch_env!(:tore, :uploads_dir)
    Plug.Static.init(at: "/uploads", from: dir, gzip: false)
  end

  @impl Plug
  def call(conn, opts), do: Plug.Static.call(conn, opts)
end
