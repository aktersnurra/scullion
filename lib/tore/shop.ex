defmodule Tore.Shop do
  alias Tore.{EventStore, Shop.Decider, Shop.Commands, Shop.Aggregator, Pantry}
  alias Phoenix.PubSub

  @llm Application.compile_env(:tore, :llm_client)
  @pubsub Tore.PubSub
  @topic "shop_list"

  def load_list(list_id) do
    EventStore.load(list_id, Decider)
  end

  def build_list(list_id, week_start, recipe_ids) do
    all_items = Aggregator.aggregate_by_ids(recipe_ids)
    pantry = Pantry.list_inventory()

    items =
      if pantry == [] do
        all_items
      else
        case filter_pantry_items(all_items, pantry) do
          {:ok, filtered} -> filtered
          _ -> all_items
        end
      end

    EventStore.reset(list_id)
    run(list_id, %Commands.BuildList{week_start: week_start, items: items})
  end

  def add_item(list_id, name, quantity, unit, user_id) do
    section =
      case classify_grocery_item(name) do
        {:ok, s} -> s
        _ -> :other
      end

    run(list_id, %Commands.AddItem{
      item_id: Ecto.UUID.generate(),
      name: name,
      quantity: quantity,
      unit: unit,
      section: section,
      added_by: user_id
    })
  end

  @valid_sections ~w(produce meat fish dairy deli frozen bread dry_goods canned beverages herbs_spices condiments household other)

  defp filter_pantry_items(ingredients, pantry) do
    {system, user} = Tore.LLM.Prompts.filter_pantry_items(ingredients, pantry)

    fallback = Application.get_env(:tore, :openrouter_check_model_fallback, "openai/gpt-oss-120b")

    case @llm.text(system, user,
           model: fallback,
           response_format: Tore.LLM.Prompts.filter_pantry_schema()
         ) do
      {:ok, items, _usage} when is_list(items) -> {:ok, build_filter_result(items)}
      {:ok, %{"items" => items}, _usage} when is_list(items) -> {:ok, build_filter_result(items)}
      {:ok, _, _} -> {:error, :invalid_response}
      {:error, _} = err -> err
    end
  end

  defp classify_grocery_item(name) do
    {system, user} = Tore.LLM.Prompts.classify_grocery_item(name)

    case @llm.text(system, user, []) do
      {:ok, %{"section" => section}, _usage} -> {:ok, to_section_atom(section)}
      {:ok, _, _} -> {:error, :invalid_response}
      {:error, _} = err -> err
    end
  end

  defp build_filter_result(items) do
    items
    |> Enum.map(&Map.put(&1, "name", &1["name"] || &1["item"] || &1["ingredient"]))
    |> Enum.filter(&is_binary(&1["name"]))
    |> Enum.map(fn i ->
      qty =
        case i["quantity"] do
          nil -> nil
          n when is_number(n) -> n
          s when is_binary(s) -> s
          _ -> nil
        end

      %{
        id: Ecto.UUID.generate(),
        name: i["name"],
        quantity: qty,
        unit: i["unit"],
        section: to_section_atom(i["section"]),
        checked: false
      }
    end)
  end

  defp to_section_atom(s) when is_binary(s) and s in @valid_sections, do: String.to_atom(s)
  defp to_section_atom(_), do: :other

  def remove_item(list_id, item_id, user_id) do
    run(list_id, %Commands.RemoveItem{item_id: item_id, removed_by: user_id})
  end

  def check_item(list_id, item_id, user_id) do
    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <-
           Decider.decide(%Commands.CheckItem{item_id: item_id, checked_by: user_id}, state),
         :ok <- EventStore.append(list_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      item = Map.get(state.items, item_id)
      if item, do: Pantry.add_item(%{name: item.name, quantity: item.quantity, unit: item.unit})
      {:ok, events}
    end
  end

  def uncheck_item(list_id, item_id, user_id) do
    run(list_id, %Commands.UncheckItem{item_id: item_id, unchecked_by: user_id})
  end

  def export_list(list_id) do
    with {:ok, state} <- EventStore.load(list_id, Decider) do
      lines =
        state.items
        |> Map.values()
        |> Enum.reject(& &1.checked)
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn item ->
          qty = if item.quantity, do: "#{item.quantity} #{item.unit} ", else: ""
          "- #{qty}#{item.name}"
        end)

      {:ok, Enum.join(lines, "\n")}
    end
  end

  defp run(list_id, command) do
    with {:ok, state} <- EventStore.load(list_id, Decider),
         {:ok, events} <- Decider.decide(command, state),
         :ok <- EventStore.append(list_id, events) do
      PubSub.broadcast(@pubsub, @topic, {:events, events})
      {:ok, events}
    end
  end
end
