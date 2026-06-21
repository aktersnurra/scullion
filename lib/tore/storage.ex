defmodule Tore.Storage do
  @callback put_object(
              bucket :: String.t(),
              key :: String.t(),
              body :: binary(),
              opts :: keyword()
            ) ::
              {:ok, String.t()} | {:error, term()}

  @callback get_object(bucket :: String.t(), key :: String.t()) ::
              {:ok, binary()} | {:error, term()}

  @callback get_object_url(bucket :: String.t(), key :: String.t()) :: String.t()

  @callback delete_object(bucket :: String.t(), key :: String.t()) :: :ok | {:error, term()}

  @callback list_object_keys(bucket :: String.t(), prefix :: String.t()) ::
              {:ok, [String.t()]} | {:error, term()}

  def client, do: Application.fetch_env!(:tore, :storage_client)
end
