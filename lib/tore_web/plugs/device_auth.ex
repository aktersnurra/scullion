defmodule ToreWeb.Plugs.DeviceAuth do
  import Plug.Conn
  alias Tore.Accounts

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    token =
      case get_req_header(conn, "x-device-token") do
        [t | _] -> t
        [] -> conn.params["token"]
      end

    case Accounts.verify_device_token(token || "") do
      {:ok, :kiosk} ->
        assign(conn, :current_user, %{role: :kiosk})

      {:error, _} ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
