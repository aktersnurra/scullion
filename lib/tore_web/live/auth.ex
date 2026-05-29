defmodule ToreWeb.Live.Auth do
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias Tore.Accounts

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = socket |> mount_current_user(session) |> attach_current_path()

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = socket |> mount_current_user(session) |> attach_current_path()

    case socket.assigns.current_user do
      %{role: :admin} -> {:cont, socket}
      nil -> {:halt, redirect(socket, to: "/login")}
      _ -> {:halt, redirect(socket, to: "/")}
    end
  end

  def on_mount(:require_device_token, _params, session, socket) do
    case session["device_token"] do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      raw_token ->
        case Accounts.verify_device_token(raw_token) do
          {:ok, :kiosk} -> {:cont, socket}
          {:error, _} -> {:halt, redirect(socket, to: "/login")}
        end
    end
  end

  defp attach_current_path(socket) do
    socket
    |> assign(:current_path, "/")
    |> attach_hook(:current_path, :handle_params, fn _params, url, socket ->
      path = URI.parse(url).path || "/"
      {:cont, assign(socket, :current_path, path)}
    end)
  end

  defp mount_current_user(socket, session) do
    case session["user_id"] do
      nil ->
        Gettext.put_locale(ToreWeb.Gettext, "sv")
        assign(socket, :current_user, nil)

      user_id ->
        user = Accounts.get_user!(user_id)
        Gettext.put_locale(ToreWeb.Gettext, user.locale || "sv")
        assign(socket, :current_user, user)
    end
  rescue
    Ecto.NoResultsError ->
      Gettext.put_locale(ToreWeb.Gettext, "sv")
      assign(socket, :current_user, nil)
  end
end
