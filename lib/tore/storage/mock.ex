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
  def get_object_url(bucket, key) do
    "http://mock-storage/#{bucket}/#{key}"
  end

  @impl true
  def delete_object(bucket, key) do
    Agent.update(__MODULE__, &Map.delete(&1, {bucket, key}))
    :ok
  end

  def get(bucket, key) do
    Agent.get(__MODULE__, &Map.get(&1, {bucket, key}))
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
