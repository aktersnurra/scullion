defmodule ScullionWeb.SettingsLive do
  use ScullionWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>Settings</div>
    """
  end
end
