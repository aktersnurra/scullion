defmodule ToreWeb.Plugs.KioskAuth do
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  alias Tore.Accounts

  @behaviour Plug
  @cookie "_tore_device_token"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    session_token = get_session(conn, "device_token")

    raw =
      if session_token && session_token != "" do
        session_token
      else
        conn = fetch_cookies(conn)
        conn.cookies[@cookie]
      end

    case Accounts.verify_device_token(raw || "") do
      {:ok, :kiosk} ->
        put_session(conn, "device_token", raw)

      {:error, _} ->
        conn |> redirect(to: "/login") |> halt()
    end
  end
end
