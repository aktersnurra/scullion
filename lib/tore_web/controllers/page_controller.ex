defmodule ToreWeb.PageController do
  use ToreWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
