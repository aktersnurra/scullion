defmodule Scullion.Repo do
  use Ecto.Repo,
    otp_app: :scullion,
    adapter: Ecto.Adapters.SQLite3
end
