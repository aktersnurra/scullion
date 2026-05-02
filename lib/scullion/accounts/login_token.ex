defmodule Scullion.Accounts.LoginToken do
  use GenServer

  @table :scullion_login_tokens
  @ttl 30

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @spec create(term()) :: String.t()
  def create(user_id) do
    token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    expires = System.system_time(:second) + @ttl
    :ets.insert(@table, {token, user_id, expires})
    token
  end

  @spec consume(String.t()) :: {:ok, term()} | {:error, :invalid | :expired}
  def consume(token) when is_binary(token) do
    case :ets.lookup(@table, token) do
      [{^token, user_id, expires}] ->
        :ets.delete(@table, token)
        if System.system_time(:second) < expires, do: {:ok, user_id}, else: {:error, :expired}

      [] ->
        {:error, :invalid}
    end
  end

  def consume(_), do: {:error, :invalid}

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end
end
