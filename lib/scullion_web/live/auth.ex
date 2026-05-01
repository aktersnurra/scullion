defmodule ScullionWeb.Live.Auth do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias Scullion.Accounts

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_user(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_user(session, socket)

    case socket.assigns.current_user do
      %{role: :admin} -> {:cont, socket}
      nil -> {:halt, redirect(socket, to: "/login")}
      _ -> {:halt, redirect(socket, to: "/")}
    end
  end

  defp mount_current_user(session, socket) do
    case session["user_id"] do
      nil ->
        assign(socket, :current_user, nil)

      user_id ->
        user = Accounts.get_user!(user_id)
        assign(socket, :current_user, user)
    end
  rescue
    Ecto.NoResultsError -> assign(socket, :current_user, nil)
  end
end
