defmodule ScullionWeb.PageController do
  use ScullionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
