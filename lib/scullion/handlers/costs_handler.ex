defmodule Scullion.Handlers.CostsHandler do
  @llm Application.compile_env(:scullion, :llm_client)

  def parse_and_log_receipt(image_binary, user_id) do
    with {:ok, line_items} <- @llm.parse_receipt_image(image_binary) do
      Scullion.Costs.log_receipt(%{
        line_items: line_items,
        user_id: user_id
      })
    end
  end

  def log_dining_out(attrs, user_id) do
    Scullion.Costs.log_dining_out(Map.put(attrs, :user_id, user_id))
  end
end
