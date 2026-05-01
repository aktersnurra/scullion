defmodule ScullionWeb.PlannerLive do
  use ScullionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>Planner</div>
    """
  end
end
