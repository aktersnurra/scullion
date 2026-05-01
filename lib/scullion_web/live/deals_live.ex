defmodule ScullionWeb.DealsLive do
  use ScullionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>Deals</div>
    """
  end
end
