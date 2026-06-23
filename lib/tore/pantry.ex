defmodule Tore.Pantry do
  import Ecto.Query
  alias Tore.Repo
  alias Tore.Pantry.PantryItem
  alias Tore.Recipes.Ingredient

  def parse_image(image_binary) do
    {system, user} = Tore.LLM.Prompts.parse_pantry_image()

    with {:ok, data, _usage} <-
           Tore.LLM.vision([{:image, image_binary}], system, user,
             response_format: Tore.LLM.Prompts.pantry_json_schema()
           ) do
      items =
        Enum.map(data["items"] || [], fn it ->
          %{
            name: it["name"],
            quantity: parse_decimal(it["quantity"]),
            unit: it["unit"],
            category: it["category"]
          }
        end)

      {:ok, items}
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(n) when is_number(n), do: Decimal.from_float(n * 1.0)
  defp parse_decimal(s) when is_binary(s), do: Decimal.new(s)

  def confirm_items(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case add_item(item) do
        {:ok, pantry_item} -> {:cont, {:ok, [pantry_item | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      error -> error
    end
  end

  @doc """
  Catalogue snapshot used to ground the LLM canonicaliser.
  """
  @spec catalogue() :: [%{key: String.t(), name: String.t(), category: String.t() | nil}]
  def catalogue do
    Repo.all(from i in Ingredient, select: %{key: i.key, name: i.name, category: i.category})
  end

  @doc """
  Look up an ingredient in the catalogue by free-text name. Returns the
  single matching row (with `default_unit`) when one row's name is a
  bidirectional substring of the query, otherwise `nil`. Used by the
  shopping-list "add milk" path to infer "1 L".
  """
  @spec lookup_catalogue_ingredient(String.t()) :: Ingredient.t() | nil
  def lookup_catalogue_ingredient(query) when is_binary(query) do
    needle = String.downcase(String.trim(query))

    if needle == "" do
      nil
    else
      Repo.all(Ingredient)
      |> Enum.find(fn ing ->
        name = String.downcase(ing.name)
        String.contains?(name, needle) or String.contains?(needle, name)
      end)
    end
  end

  @doc """
  Send raw pantry items through the LLM canonicaliser. Returns a list of
  `{raw_name, catalogue_name, category, default_unit, matched_key}` maps.
  """
  @spec canonicalise([map()], String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def canonicalise(items, locale) do
    {system, user} = Tore.LLM.Prompts.canonicalise_pantry_items(items, locale, catalogue())

    case Tore.LLM.text(system, user, response_format: Tore.LLM.Prompts.canonicalise_pantry_schema()) do
      {:ok, %{"items" => norm}, _usage} when is_list(norm) ->
        {:ok,
         Enum.map(norm, fn it ->
           %{
             raw_name: it["raw_name"],
             catalogue_name: it["catalogue_name"],
             category: it["category"],
             default_unit: it["default_unit"],
             matched_key: it["matched_key"]
           }
         end)}

      {:ok, _, _} ->
        {:error, :invalid_response}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Upsert a single canonicalised pantry belief.

  Expects an attrs map with `catalogue_name`, optional `matched_key`, plus
  `quantity`, `unit`, `category`, `default_unit`, `provenance`, `last_seen_at`.
  Resolves the ingredient by key (find-or-create), then bumps an existing
  pantry row keyed on ingredient_id, or inserts a new one. The pantry row
  always shows the catalogue name — never the receipt's product variant.

  Returns `{:ok, %PantryItem{}, :added | :bumped}`.
  """
  @spec upsert_belief(map()) :: {:ok, PantryItem.t(), :added | :bumped} | {:error, term()}
  def upsert_belief(attrs) do
    Repo.transaction(fn ->
      ingredient = find_or_create_ingredient(attrs)

      case Repo.get_by(PantryItem, ingredient_id: ingredient.id) do
        nil ->
          {:ok, item} =
            attrs
            |> base_pantry_attrs(ingredient)
            |> Map.put(:quantity, attrs[:quantity])
            |> add_item()

          {item, :added}

        existing ->
          {:ok, item} = bump_existing(existing, attrs)
          {item, :bumped}
      end
    end)
    |> case do
      {:ok, {item, change}} -> {:ok, item, change}
      {:error, _} = err -> err
    end
  end

  defp find_or_create_ingredient(attrs) do
    key =
      case attrs[:matched_key] do
        k when is_binary(k) and k != "" -> k
        _ -> Ingredient.to_key(attrs[:catalogue_name] || attrs[:name] || "")
      end

    case Repo.get_by(Ingredient, key: key) do
      nil ->
        {:ok, ing} =
          %Ingredient{}
          |> Ingredient.changeset(%{
            name: attrs[:catalogue_name] || attrs[:name],
            key: key,
            category: attrs[:category],
            default_unit: attrs[:default_unit] || attrs[:unit]
          })
          |> Repo.insert()

        ing

      ing ->
        ing
    end
  end

  # Pantry row always shows the ingredient's catalogue name — receipt-specific
  # variants (brand, pack size, fat percentage) live on the cost ledger, not
  # in the pantry.
  defp base_pantry_attrs(attrs, ingredient) do
    %{
      name: ingredient.name,
      unit: attrs[:unit] || ingredient.default_unit,
      category: attrs[:category] || ingredient.category,
      provenance: attrs[:provenance] || "manual",
      last_seen_at: attrs[:last_seen_at] || now(),
      ingredient_id: ingredient.id
    }
  end

  defp bump_existing(%PantryItem{} = item, attrs) do
    new_qty =
      case {to_decimal(item.quantity), to_decimal(attrs[:quantity])} do
        {nil, q} -> q
        {q, nil} -> q
        {a, b} -> Decimal.add(a, b)
      end

    item
    |> PantryItem.changeset(%{
      quantity: new_qty,
      unit: item.unit || attrs[:unit],
      last_seen_at: attrs[:last_seen_at] || now(),
      provenance: attrs[:provenance] || item.provenance
    })
    |> Repo.update()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, _} -> d
      :error -> nil
    end
  end

  @spec add_item(map()) :: {:ok, PantryItem.t()} | {:error, Ecto.Changeset.t()}
  def add_item(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.put_new(:added_at, Date.utc_today())
      |> Map.put_new(:provenance, "manual")
      |> Map.put_new(:last_seen_at, now)

    %PantryItem{} |> PantryItem.changeset(attrs) |> Repo.insert()
  end

  @spec remove_item(integer()) :: :ok | {:error, :not_found}
  def remove_item(item_id) do
    case Repo.get(PantryItem, item_id) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item) |> then(fn _ -> :ok end)
    end
  end

  @spec list_inventory() :: [PantryItem.t()]
  def list_inventory do
    Repo.all(from p in PantryItem, order_by: p.name)
  end

  @doc """
  Resolve a free-text name to a single pantry item by case-insensitive
  bidirectional substring match. Returns the item if exactly one row
  matches, otherwise `{:ambiguous, candidates}` or `{:error, :not_found}`.

  Used by the agent's tool path so "we're out of milk" can find the
  pantry row without the agent needing to know item ids.
  """
  @spec find_by_name_fuzzy(String.t()) ::
          {:ok, PantryItem.t()} | {:ambiguous, [PantryItem.t()]} | {:error, :not_found}
  def find_by_name_fuzzy(query) when is_binary(query) do
    needle = String.downcase(String.trim(query))

    if needle == "" do
      {:error, :not_found}
    else
      matches =
        list_inventory()
        |> Enum.filter(fn item ->
          name = String.downcase(item.name)
          String.contains?(name, needle) or String.contains?(needle, name)
        end)

      case matches do
        [] -> {:error, :not_found}
        [one] -> {:ok, one}
        many -> {:ambiguous, many}
      end
    end
  end

  @spec list_inventory_grouped() :: [{atom() | nil, [PantryItem.t()]}]
  def list_inventory_grouped do
    items = Repo.all(from p in PantryItem, order_by: p.name)

    grouped = Enum.group_by(items, & &1.category)

    PantryItem.categories()
    |> Enum.flat_map(fn key ->
      str = Atom.to_string(key)

      case Map.get(grouped, str) do
        nil -> []
        bucket -> [{key, bucket}]
      end
    end)
    |> then(fn acc ->
      case Map.get(grouped, nil) do
        nil -> acc
        uncategorised -> acc ++ [{nil, uncategorised}]
      end
    end)
  end
end
