defmodule Tore.Pantry.PantryItem do
  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    :dairy,
    :meat,
    :produce,
    :frozen,
    :dry_goods,
    :canned,
    :herbs_spices,
    :condiments,
    :other
  ]

  @provenances ~w[manual receipt vision belief grocery_checkoff]
  @beliefs ~w[confirmed probable uncertain missing]

  def categories, do: @categories

  def category_values, do: Enum.map(@categories, &Atom.to_string/1)

  def provenances, do: @provenances

  def beliefs, do: @beliefs

  @doc """
  Maps a provenance value to the belief we'd assign by default. Receipt and
  grocery-checkoff items are downgraded to `probable` because they tell us
  what was bought, not whether it's still in the cupboard.
  """
  def derive_belief("manual"), do: "confirmed"
  def derive_belief("vision"), do: "confirmed"
  def derive_belief("receipt"), do: "probable"
  def derive_belief("grocery_checkoff"), do: "probable"
  def derive_belief("belief"), do: "uncertain"
  def derive_belief(_), do: "confirmed"

  # Belief decays with recency: the longer since we last observed the
  # item, the less confident we are it's still there. Pure read-side
  # projection — the stored row keeps the strongest observation; the UI
  # asks for the *effective* belief at render time.
  @confirmed_max_age_days 14
  @probable_max_age_days 30

  @doc """
  Decay the stored belief by `last_seen_at`. Returns the belief atom the
  UI should render. Stored `:uncertain` / `:missing` are returned as-is;
  rows with no `last_seen_at` (manual adds that bypassed the receipt
  path) keep their stored belief.
  """
  @spec effective_belief(%__MODULE__{}, DateTime.t()) :: :confirmed | :probable | :uncertain | :missing
  def effective_belief(%__MODULE__{belief: belief, last_seen_at: nil}, _now),
    do: String.to_existing_atom(belief || "uncertain")

  def effective_belief(%__MODULE__{belief: belief, last_seen_at: %DateTime{} = seen}, %DateTime{} = now) do
    age_days = DateTime.diff(now, seen, :day)
    decay(belief, age_days)
  end

  defp decay("confirmed", age) when age > @probable_max_age_days, do: :uncertain
  defp decay("confirmed", age) when age > @confirmed_max_age_days, do: :probable
  defp decay("confirmed", _), do: :confirmed
  defp decay("probable", age) when age > @probable_max_age_days, do: :uncertain
  defp decay("probable", _), do: :probable
  defp decay("uncertain", _), do: :uncertain
  defp decay("missing", _), do: :missing
  defp decay(_, _), do: :uncertain

  schema "pantry_items" do
    field :name, :string
    field :quantity, :decimal
    field :unit, :string
    field :category, :string
    field :added_at, :date
    field :expires_at, :date
    field :provenance, :string, default: "manual"
    field :belief, :string, default: "confirmed"
    field :last_seen_at, :utc_datetime
    belongs_to :ingredient, Tore.Recipes.Ingredient
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :category,
      :ingredient_id,
      :added_at,
      :expires_at,
      :provenance,
      :belief,
      :last_seen_at
    ])
    |> validate_required([:name, :added_at, :provenance])
    |> update_change(:name, &normalize_name/1)
    |> validate_inclusion(:category, category_values())
    |> validate_inclusion(:provenance, @provenances)
    |> validate_inclusion(:belief, @beliefs)
  end

  defp normalize_name(name), do: name |> String.trim() |> String.downcase()
end
