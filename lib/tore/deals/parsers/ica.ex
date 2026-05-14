defmodule Tore.Deals.Parsers.ICA do
  @behaviour Tore.Deals.Parsers.Parser

  @impl Tore.Deals.Parsers.Parser
  def parse(html) do
    with {:ok, offers} <- extract_initial_data(html),
         {:ok, offers} <- extract_offers(offers) do
      deals = Enum.map(offers, &to_deal/1)
      {:ok, deals}
    end
  end

  defp extract_initial_data(html) do
    # ICA's SPA embeds offers directly in the SSR HTML as __INITIAL_DATA__.
    # We extract only the weeklyOffers array to avoid parsing the full (invalid) JSON blob.
    case Regex.run(~r/"weeklyOffers":(\[.+?\]),"compensationOffersStatus"/s, html) do
      [_, arr_str] ->
        cleaned = String.replace(arr_str, ":undefined", ":null")
        Jason.decode(cleaned)

      _ ->
        {:error, :no_initial_data}
    end
  end

  defp extract_offers(offers) when is_list(offers), do: {:ok, offers}
  defp extract_offers(_), do: {:error, :no_offers}

  defp to_deal(offer) do
    details = offer["details"] || %{}
    mechanics = offer["parsedMechanics"] || %{}

    price_str = "#{mechanics["value2"]}#{mechanics["value4"]}"
    valid_until = parse_date(offer["validTo"])

    %{
      store: "ica",
      product_name: details["name"] || "",
      brand: nilify(details["brand"]),
      size: nilify(details["packageInformation"]),
      price: parse_price(mechanics["value2"]),
      price_unit: nilify(mechanics["unitSign"]),
      offer_condition: nilify(details["mechanicInfo"] || price_str),
      valid_until: valid_until,
      source: :scraped
    }
  end

  defp parse_price(nil), do: nil
  defp parse_price(""), do: nil

  defp parse_price(str) do
    case Regex.run(~r/(\d+[,.]?\d*)/, str) do
      [_, digits] -> digits |> String.replace(",", ".") |> Decimal.new()
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(str) do
    case NaiveDateTime.from_iso8601(str) do
      {:ok, ndt} -> NaiveDateTime.to_date(ndt)
      _ -> nil
    end
  end

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(v), do: v
end
