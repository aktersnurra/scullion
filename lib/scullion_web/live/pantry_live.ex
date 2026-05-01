defmodule ScullionWeb.PantryLive do
  use ScullionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>Pantry</div>
    """
  end
end
