defmodule ScullionWeb.SessionController do
  use ScullionWeb, :controller
  alias Scullion.Accounts.LoginToken

  def confirm(conn, %{"t" => token}) do
    case LoginToken.consume(token) do
      {:ok, user_id} ->
        conn
        |> put_session(:user_id, user_id)
        |> redirect(to: "/")

      {:error, _} ->
        conn
        |> put_flash(:error, "Login link expired. Please try again.")
        |> redirect(to: "/login")
    end
  end

  def confirm(conn, _params) do
    conn
    |> put_flash(:error, "Invalid login attempt.")
    |> redirect(to: "/login")
  end
end
