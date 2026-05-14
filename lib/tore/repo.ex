defmodule Tore.Repo do
  use Ecto.Repo,
    otp_app: :tore,
    adapter: Ecto.Adapters.SQLite3
end
