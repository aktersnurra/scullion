defmodule Tore.Storage.S3 do
  @behaviour Tore.Storage

  @impl true
  def put_object(bucket, key, body, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    bucket
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, get_object_url(bucket, key)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_object(bucket, key) do
    bucket
    |> ExAws.S3.get_object(key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_object_url(bucket, key) do
    config = ExAws.Config.new(:s3)
    scheme = config[:scheme] || "http://"
    host = config[:host] || "localhost"
    port = config[:port] || 3900
    "#{scheme}#{host}:#{port}/#{bucket}/#{key}"
  end

  @impl true
  def delete_object(bucket, key) do
    bucket
    |> ExAws.S3.delete_object(key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_object_keys(bucket, prefix \\ "") do
    bucket
    |> ExAws.S3.list_objects(prefix: prefix)
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{contents: contents}}} -> {:ok, Enum.map(contents, & &1.key)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_buckets_exist() :: :ok
  def ensure_buckets_exist do
    # Single-attempt probe so a stopped Garage doesn't spam 10 retries at boot
    # or every time an image upload is attempted.
    opts = [retries: [max_attempts: 1]]

    Enum.each(Tore.Storage.Buckets.all(), fn bucket ->
      case bucket |> ExAws.S3.put_bucket("garage") |> ExAws.request(opts) do
        {:ok, _} ->
          :ok

        {:error, {:http_error, 409, _}} ->
          :ok

        {:error, :econnrefused} ->
          require Logger
          Logger.info("S3 (Garage) unreachable at boot; skipping bucket probe for #{bucket}")

        {:error, reason} ->
          require Logger
          Logger.warning("Could not ensure S3 bucket #{bucket} exists: #{inspect(reason)}")
      end
    end)
  end
end
