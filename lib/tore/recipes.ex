defmodule Tore.Recipes do
  import Ecto.Query
  alias Tore.Repo
  alias Tore.Recipes.{Recipe, Ingredient, RecipeIngredient, Tag}

  @http Application.compile_env(:tore, :http_client)
  @image_gen Application.compile_env(:tore, :image_gen_client)

  @spec create(map()) :: {:ok, Recipe.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    {tag_names, attrs} = Map.pop(attrs, :tags, [])
    {ingredients, attrs} = Map.pop(attrs, :ingredients, [])

    Repo.transaction(fn ->
      with {:ok, recipe} <- insert_recipe(attrs),
           :ok <- insert_ingredients(recipe, ingredients),
           {:ok, recipe} <- attach_tags(recipe, tag_names) do
        recipe
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, recipe} ->
        maybe_generate_image(recipe, Map.get(attrs, :image_url))
        {:ok, get!(recipe.id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec update(Recipe.t(), map()) :: {:ok, Recipe.t()} | {:error, Ecto.Changeset.t()}
  def update(%Recipe{} = recipe, attrs) do
    {tag_names, attrs} = Map.pop(attrs, :tags, nil)
    {ingredients, attrs} = Map.pop(attrs, :ingredients, nil)

    Repo.transaction(fn ->
      with {:ok, updated} <- do_update(recipe, attrs),
           {:ok, updated} <- maybe_update_tags(updated, tag_names),
           {:ok, updated} <- maybe_update_ingredients(updated, ingredients) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, recipe} -> {:ok, get!(recipe.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get!(term()) :: Recipe.t()
  def get!(id) do
    Repo.get!(Recipe, id) |> Repo.preload([:tags, recipe_ingredients: :ingredient])
  end

  @spec list(keyword()) :: [Recipe.t()]
  def list(opts \\ []) do
    Recipe
    |> filter_tags(opts[:tags])
    |> filter_type(opts[:type])
    |> filter_max_minutes(opts[:max_minutes])
    |> filter_weeknight(opts[:weeknight_friendly])
    |> apply_sort(opts[:sort])
    |> Repo.all()
    |> Repo.preload([:tags])
  end

  @spec search(String.t()) :: [Recipe.t()]
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    term = "%#{query}%"

    from(r in Recipe,
      left_join: ri in RecipeIngredient,
      on: ri.recipe_id == r.id,
      left_join: i in Ingredient,
      on: i.id == ri.ingredient_id,
      where: like(r.title, ^term) or like(i.name, ^term),
      distinct: true
    )
    |> Repo.all()
    |> Repo.preload([:tags])
  end

  def search(_), do: []

  @spec delete(Recipe.t()) :: {:ok, Recipe.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Recipe{} = recipe), do: Repo.delete(recipe)

  @spec record_used(integer()) :: :ok
  def record_used(recipe_id) do
    from(r in Recipe, where: r.id == ^recipe_id)
    |> Repo.update_all(set: [last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)])

    :ok
  end

  @spec scrape_from_url(String.t(), String.t() | nil) :: {:ok, Recipe.t()} | {:error, term()}
  def scrape_from_url(url, locale \\ nil) do
    scrape_and_create(url, locale)
  end

  @llm Application.compile_env(:tore, :llm_client)

  @spec extract_from_images([binary()], String.t() | nil) :: {:ok, map()} | {:error, term()}
  def extract_from_images(binaries, locale \\ nil) do
    @llm.parse_recipe_images(binaries, locale)
  end

  @spec suggest_substitution(String.t(), String.t()) ::
          {:ok, %{suggestion: String.t(), updated_steps: String.t() | nil}} | {:error, term()}
  def suggest_substitution(missing, recipe_context) do
    @llm.suggest_substitution(missing, recipe_context)
  end

  @spec cook_mode_steps(map()) ::
          {:ok, %{do_first: [String.t()], while_cooking: [String.t()], finish: [String.t()]}}
          | {:error, term()}
  def cook_mode_steps(recipe) do
    @llm.cook_mode_steps(recipe)
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp insert_recipe(attrs) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_ingredients(_recipe, []), do: :ok

  defp insert_ingredients(recipe, ingredients) do
    Enum.each(ingredients, fn ing_attrs ->
      name = Map.get(ing_attrs, :name) || Map.get(ing_attrs, "name")

      {:ok, ingredient} =
        %Ingredient{}
        |> Ingredient.changeset(%{name: name})
        |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
        |> case do
          {:ok, %Ingredient{id: nil}} -> {:ok, Repo.get_by!(Ingredient, name: name)}
          result -> result
        end

      %RecipeIngredient{}
      |> RecipeIngredient.changeset(%{
        recipe_id: recipe.id,
        ingredient_id: ingredient.id,
        quantity: Map.get(ing_attrs, :quantity) || Map.get(ing_attrs, "quantity"),
        unit: Map.get(ing_attrs, :unit) || Map.get(ing_attrs, "unit"),
        notes: Map.get(ing_attrs, :notes) || Map.get(ing_attrs, "notes")
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp attach_tags(recipe, []), do: {:ok, recipe}

  defp attach_tags(recipe, tag_names) do
    tags = Enum.map(tag_names, &upsert_tag/1)
    recipe = Repo.preload(recipe, :tags)

    recipe
    |> Recipe.tag_changeset(tags)
    |> Repo.update()
  end

  defp upsert_tag(name) do
    %Tag{}
    |> Tag.changeset(%{name: name})
    |> Repo.insert(on_conflict: :nothing, conflict_target: :name)
    |> case do
      {:ok, %Tag{id: nil}} -> Repo.get_by!(Tag, name: name)
      {:ok, tag} -> tag
    end
  end

  defp do_update(recipe, attrs) do
    recipe
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_update_tags(recipe, nil), do: {:ok, recipe}

  defp maybe_update_tags(recipe, tag_names) do
    tags = Enum.map(tag_names, &upsert_tag/1)
    recipe = Repo.preload(recipe, :tags)

    recipe
    |> Recipe.tag_changeset(tags)
    |> Repo.update()
  end

  defp maybe_update_ingredients(recipe, nil), do: {:ok, recipe}

  defp maybe_update_ingredients(recipe, ingredients) do
    Repo.delete_all(from ri in RecipeIngredient, where: ri.recipe_id == ^recipe.id)
    # insert_ingredients uses Repo.insert! — raises on failure, transaction rolls back
    insert_ingredients(recipe, ingredients)
    {:ok, recipe}
  end

  defp maybe_generate_image(recipe, image_url) do
    loaded = Repo.preload(recipe, recipe_ingredients: :ingredient)

    Task.start(fn ->
      generate_image(loaded, image_url)
    end)
  end

  @spec scrape_and_create(String.t(), String.t() | nil) ::
          {:ok, Recipe.t()} | {:error, term()}
  def scrape_and_create(url, locale \\ nil) do
    with {:ok, html} <- @http.fetch(url),
         {:ok, attrs} <- parse_or_extract(html, locale) do
      create(Map.put(attrs, :source_url, url))
    end
  end

  @spec generate_image(Recipe.t(), String.t() | nil) :: :ok | {:error, term()}
  def generate_image(recipe, image_url) do
    storage = Tore.Storage.client()
    key = "recipes/#{recipe.id}/#{Ecto.UUID.generate()}.jpg"

    with {:ok, binary} <- fetch_or_generate(recipe, image_url),
         {:ok, url} <-
           storage.put_object(Tore.Storage.Buckets.recipes(), key, binary,
             content_type: "image/jpeg"
           ) do
      Repo.update_all(
        from(r in Recipe, where: r.id == ^recipe.id),
        set: [image_path: url]
      )

      :ok
    end
  end

  defp parse_or_extract(html, locale) do
    with {:error, :not_found} <- Tore.Recipes.Parser.parse_html(html) do
      @llm.extract_recipe_from_html(html, locale)
    end
  end

  defp fetch_or_generate(_recipe, image_url) when is_binary(image_url) and image_url != "" do
    @http.fetch(image_url)
  end

  defp fetch_or_generate(recipe, _image_url) do
    @image_gen.generate_food_image(recipe.title, recipe.instructions)
  end

  # ── Query filters ──────────────────────────────────────────────────────────

  defp filter_tags(query, nil), do: query
  defp filter_tags(query, []), do: query

  defp filter_tags(query, tag_names) do
    Enum.reduce(tag_names, query, fn name, q ->
      from r in q,
        join: rt in "recipe_tags",
        on: rt.recipe_id == r.id,
        join: t in Tag,
        on: t.id == rt.tag_id and t.name == ^name
    end)
  end

  defp filter_type(query, nil), do: query
  defp filter_type(query, :all), do: query
  defp filter_type(query, type), do: from(r in query, where: r.recipe_type == ^type)

  defp filter_max_minutes(query, nil), do: query
  defp filter_max_minutes(query, :any), do: query

  defp filter_max_minutes(query, max) when is_integer(max) do
    from r in query,
      where: coalesce(r.prep_time_minutes, 0) + coalesce(r.cook_time_minutes, 0) <= ^max
  end

  defp filter_weeknight(query, true) do
    query
    |> filter_max_minutes(45)
    |> filter_tags(["quick"])
  end

  defp filter_weeknight(query, _), do: query

  defp apply_sort(query, :last_used) do
    from r in query, order_by: [desc_nulls_last: r.last_used_at]
  end

  defp apply_sort(query, :alphabetical) do
    from r in query, order_by: [asc: r.title]
  end

  defp apply_sort(query, _) do
    from r in query, order_by: [desc: r.inserted_at]
  end
end
