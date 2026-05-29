defmodule Tore.Family do
  alias Tore.{Repo, Family.FamilySchema, Household.Preferences}

  @spec get_family!() :: FamilySchema.t()
  def get_family! do
    case Repo.one(FamilySchema) do
      nil ->
        %FamilySchema{}
        |> FamilySchema.changeset(%{name: "Home", locale: "sv"})
        |> Repo.insert!()

      family ->
        family
    end
  end

  @spec create_family(map()) :: {:ok, FamilySchema.t()} | {:error, Ecto.Changeset.t()}
  def create_family(attrs) do
    %FamilySchema{}
    |> FamilySchema.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_preferences() :: Preferences.t()
  def get_preferences do
    family = get_family!()

    case Repo.get_by(Preferences, family_id: family.id) do
      nil -> %Preferences{family_id: family.id}
      prefs -> prefs
    end
  end

  @spec update_preferences(map()) :: {:ok, Preferences.t()} | {:error, Ecto.Changeset.t()}
  def update_preferences(attrs) do
    family = get_family!()

    case Repo.get_by(Preferences, family_id: family.id) do
      nil -> %Preferences{family_id: family.id}
      existing -> existing
    end
    |> Preferences.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @spec prefs_to_dietary_guidance(Preferences.t()) :: String.t() | nil
  def prefs_to_dietary_guidance(%Preferences{} = p) do
    parts =
      [
        restrictions_line(p.dietary_restrictions),
        allergies_line(p.allergies),
        dislikes_line(p.dislikes),
        style_line(p.cooking_style),
        cuisine_line(p.cuisine_preferences)
      ]
      |> Enum.reject(&is_nil/1)

    if parts == [], do: nil, else: Enum.join(parts, "; ")
  end

  defp restrictions_line(nil), do: nil
  defp restrictions_line([]), do: nil
  defp restrictions_line(list), do: "Diet: #{Enum.join(list, ", ")}"

  defp allergies_line(nil), do: nil
  defp allergies_line([]), do: nil
  defp allergies_line(list), do: "Allergies/hard avoids: #{Enum.join(list, ", ")}"

  defp dislikes_line(nil), do: nil
  defp dislikes_line([]), do: nil
  defp dislikes_line(list), do: "Avoid too often: #{Enum.join(list, ", ")}"

  defp style_line(nil), do: nil
  defp style_line([]), do: nil
  defp style_line(list), do: "Cooking style: #{Enum.join(list, ", ")}"

  defp cuisine_line(nil), do: nil
  defp cuisine_line(map) when map == %{}, do: nil

  defp cuisine_line(map) do
    more = map |> Enum.filter(fn {_, v} -> v == "more" end) |> Enum.map(&elem(&1, 0))
    less = map |> Enum.filter(fn {_, v} -> v == "less" end) |> Enum.map(&elem(&1, 0))

    [
      if(more != [], do: "More of: #{Enum.join(more, ", ")}"),
      if(less != [], do: "Less of: #{Enum.join(less, ", ")}")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> "Cuisine: #{Enum.join(parts, "; ")}"
    end
  end
end
