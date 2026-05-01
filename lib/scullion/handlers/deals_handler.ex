defmodule Scullion.Handlers.DealsHandler do
  @http Application.compile_env(:scullion, :http_client)

  def scrape_all do
    Scullion.Deals.StoreConfig
    |> Scullion.Repo.all()
    |> Enum.filter(& &1.scrape_enabled)
    |> Enum.each(&scrape_store/1)
  end

  defp scrape_store(store_config) do
    parser = parser_for(store_config.chain)

    with {:ok, html} <- @http.fetch(store_config.url),
         {:ok, deals} <- parser.parse(html) do
      Scullion.Deals.upsert_deals(deals)
    end
  end

  defp parser_for(:ica), do: Scullion.Deals.Parsers.ICA
  defp parser_for(:coop), do: Scullion.Deals.Parsers.Coop
end
