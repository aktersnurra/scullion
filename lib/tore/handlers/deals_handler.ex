defmodule Tore.Handlers.DealsHandler do
  require Logger

  alias Tore.{Alerts, Deals, Deals.StoreConfig, Repo}

  @http Application.compile_env(:tore, :http_client)
  @llm Application.compile_env(:tore, :llm_client)

  @spec scrape_all() :: :ok
  def scrape_all do
    StoreConfig
    |> Repo.all()
    |> Enum.filter(& &1.scrape_enabled)
    |> Enum.each(&scrape_store/1)

    :ok
  end

  @spec scrape_url(String.t(), atom(), String.t() | nil) :: {:ok, integer()} | {:error, term()}
  def scrape_url(url, chain, store_name \\ nil) do
    parser = parser_for(chain)

    with {:ok, html} <- @http.fetch(url),
         {:ok, deals} <- parser.parse(html) do
      deals =
        if store_name do
          Enum.map(deals, fn d ->
            d
            |> Map.put(:store, store_name)
            |> Map.put_new(:chain, to_string(chain))
          end)
        else
          Enum.map(deals, &Map.put_new(&1, :chain, to_string(chain)))
        end

      case deals do
        [] ->
          Logger.warning("scrape returned 0 deals — parser may be broken",
            url: url,
            chain: chain
          )

          Alerts.scrape_zero_results(url, chain)
          {:ok, 0}

        _ ->
          Deals.upsert_deals(deals)
      end
    end
  end

  @spec parse_pdf(binary()) :: {:ok, integer()} | {:error, term()}
  def parse_pdf(pdf_binary) do
    with {:ok, deals} <- @llm.parse_deals_pdf(pdf_binary) do
      case deals do
        [] ->
          Logger.warning("PDF parse returned 0 deals")
          {:ok, 0}

        _ ->
          Deals.upsert_deals(deals)
      end
    end
  end

  defp scrape_store(store_config) do
    case scrape_url(store_config.url, store_config.chain, store_config.name) do
      {:ok, count} ->
        Logger.info("scraped #{count} deals", store: store_config.name, url: store_config.url)

      {:error, reason} ->
        Logger.error("scrape failed",
          store: store_config.name,
          url: store_config.url,
          reason: inspect(reason)
        )
    end
  end

  defp parser_for(:ica), do: Tore.Deals.Parsers.ICA
  defp parser_for(:coop), do: Tore.Deals.Parsers.Coop
end
