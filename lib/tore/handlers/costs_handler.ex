defmodule Tore.Handlers.CostsHandler do
  @llm Application.compile_env(:tore, :llm_client)

  def parse_receipt_image(image_binary) do
    @llm.parse_receipt_for_pantry(image_binary)
  end

  def parse_and_log_receipt(image_binary, user_id) do
    image_path = store_image(image_binary)

    with {:ok, line_items, _usage} <- @llm.parse_receipt_image(image_binary) do
      total =
        line_items
        |> Enum.map(fn item -> item.total_price || Decimal.new(0) end)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      Tore.Costs.log_receipt(%{
        date: Date.utc_today(),
        image_path: image_path,
        total_amount: total,
        user_id: user_id,
        line_items: line_items
      })
    end
  end

  def confirm_receipt(%{total: total, store_name: store_name, items: items, date: date}, user_id) do
    with {:ok, _receipt} <-
           Tore.Costs.log_receipt(%{
             date: date,
             store_name: store_name,
             total_amount: total,
             user_id: user_id,
             line_items: []
           }) do
      Tore.Handlers.PantryHandler.confirm_items(items)
    end
  end

  def log_dining_out(attrs, user_id) do
    Tore.Costs.log_dining_out(Map.put(attrs, :user_id, user_id))
  end

  defp store_image(binary) do
    filename = "#{System.unique_integer([:positive])}.jpg"
    dir = Path.join([:code.priv_dir(:tore), "static", "uploads", "receipts"])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, filename), binary)
    "/uploads/receipts/#{filename}"
  end
end
