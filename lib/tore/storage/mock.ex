defmodule Tore.Storage.Mock do
  @behaviour Tore.Storage

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @impl true
  def put_object(bucket, key, body, _opts \\ []) do
    Agent.update(__MODULE__, &Map.put(&1, {bucket, key}, body))
    {:ok, get_object_url(bucket, key)}
  end

  @impl true
  def get_object(bucket, key) do
    case Agent.get(__MODULE__, &Map.get(&1, {bucket, key})) do
      nil -> {:error, :not_found}
      body -> {:ok, body}
    end
  end

  @impl true
  def get_object_url(bucket, key) do
    "http://mock-storage/#{bucket}/#{key}"
  end

  @impl true
  def delete_object(bucket, key) do
    Agent.update(__MODULE__, &Map.delete(&1, {bucket, key}))
    :ok
  end

  @impl true
  def list_object_keys(bucket, prefix \\ "") do
    keys =
      Agent.get(__MODULE__, fn store ->
        for {{b, k}, _body} <- store, b == bucket, String.starts_with?(k, prefix), do: k
      end)

    {:ok, keys}
  end

  def get(bucket, key) do
    Agent.get(__MODULE__, &Map.get(&1, {bucket, key}))
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
