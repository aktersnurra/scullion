defmodule Tore.Deals.Parsers.ICA do
  @behaviour Tore.Deals.Parsers.Parser

  @impl Tore.Deals.Parsers.Parser
  def parse(html) do
    deals =
      Floki.parse_document!(html)
      |> Floki.find("[data-testid='offer-card'], .offer-card, article.offer")
      |> Enum.map(&extract_deal/1)
      |> Enum.reject(&is_nil/1)

    {:ok, deals}
  end

  defp extract_deal(card) do
    product_name =
      card
      |> Floki.find("[data-testid='product-name'], .product-name, h3")
      |> Floki.text()
      |> String.trim()

    if product_name == "" do
      nil
    else
      price_text =
        card
        |> Floki.find("[data-testid='price'], .price, .offer-price")
        |> Floki.text()
        |> String.trim()

      %{
        store: "ica",
        product_name: product_name,
        brand: extract_text(card, "[data-testid='brand'], .brand"),
        size: extract_text(card, "[data-testid='comparative-price'], .comparative-price, .size"),
        price: parse_price(price_text),
        price_unit: extract_price_unit(price_text),
        offer_condition: extract_text(card, "[data-testid='splash'], .splash, .offer-condition"),
        source: :scraped
      }
    end
  end

  defp extract_text(card, selector) do
    card |> Floki.find(selector) |> Floki.text() |> String.trim() |> nilify()
  end

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp parse_price(text) do
    case Regex.run(~r/(\d+[,.]?\d*)/, text) do
      [_, digits] -> digits |> String.replace(",", ".") |> Decimal.new()
      _ -> nil
    end
  end

  defp extract_price_unit(text) do
    cond do
      String.contains?(text, "/kg") -> "kr/kg"
      String.contains?(text, "/st") -> "kr/st"
      String.contains?(text, "/l") -> "kr/l"
      true -> nil
    end
  end
end
