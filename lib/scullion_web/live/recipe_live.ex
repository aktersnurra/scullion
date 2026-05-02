defmodule ScullionWeb.RecipeLive do
  use ScullionWeb, :live_view
  alias Scullion.Recipes

  @sorts [:recently_added, :last_used, :alphabetical]
  @types [:all, :meal, :component, :assembly]
  @time_filters [:any, 30, 45, 60]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       recipes: Recipes.list(),
       search: "",
       filter_tags: [],
       filter_type: :all,
       filter_max_min: :any,
       sort: :recently_added,
       scrape_url: "",
       scrape_state: :idle,
       scrape_result: nil,
       selected: nil,
       form: nil,
       error: nil,
       sorts: @sorts,
       types: @types,
       time_filters: @time_filters
     )}
  end

  # ── Events ─────────────────────────────────────────────────────────────────

  def handle_event("search", %{"query" => q}, socket) do
    recipes = if q == "", do: reload(socket), else: Recipes.search(q)
    {:noreply, assign(socket, search: q, recipes: recipes)}
  end

  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    tags =
      if tag in socket.assigns.filter_tags,
        do: List.delete(socket.assigns.filter_tags, tag),
        else: [tag | socket.assigns.filter_tags]

    {:noreply, socket |> assign(filter_tags: tags) |> reload_recipes()}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    {:noreply, socket |> assign(filter_type: parse_type(type)) |> reload_recipes()}
  end

  def handle_event("filter_time", %{"max" => max}, socket) do
    {:noreply, socket |> assign(filter_max_min: parse_time(max)) |> reload_recipes()}
  end

  def handle_event("sort", %{"by" => by}, socket) do
    {:noreply, socket |> assign(sort: parse_sort(by)) |> reload_recipes()}
  end

  def handle_event("new_recipe", _, socket) do
    {:noreply, assign(socket, form: blank_form(), selected: nil, error: nil)}
  end

  def handle_event("save_recipe", %{"recipe" => params}, socket) do
    attrs = parse_recipe_params(params)

    case socket.assigns.selected do
      nil ->
        case Recipes.create(attrs) do
          {:ok, _recipe} ->
            {:noreply, socket |> assign(form: nil, error: nil) |> reload_recipes()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: error_message(changeset))}
        end

      recipe ->
        case Recipes.update(recipe, attrs) do
          {:ok, _recipe} ->
            {:noreply, socket |> assign(form: nil, selected: nil, error: nil) |> reload_recipes()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: error_message(changeset))}
        end
    end
  end

  def handle_event("select_recipe", %{"id" => id}, socket) do
    recipe = Recipes.get!(String.to_integer(id))
    {:noreply, assign(socket, selected: recipe, form: nil, error: nil)}
  end

  def handle_event("edit_recipe", _, socket) do
    recipe = socket.assigns.selected
    {:noreply, assign(socket, form: recipe_to_form(recipe), error: nil)}
  end

  def handle_event("delete_recipe", _, socket) do
    case Recipes.delete(socket.assigns.selected) do
      {:ok, _} ->
        {:noreply, socket |> assign(selected: nil, form: nil) |> reload_recipes()}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not delete recipe")}
    end
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, selected: nil, form: nil, error: nil)}
  end

  def handle_event("scrape_url_change", %{"url" => url}, socket) do
    {:noreply, assign(socket, scrape_url: url)}
  end

  def handle_event("scrape_submit", _, socket) do
    url = String.trim(socket.assigns.scrape_url)

    if url == "" do
      {:noreply, assign(socket, error: "Enter a URL")}
    else
      send(self(), {:scrape, url})
      {:noreply, assign(socket, scrape_state: :loading, error: nil)}
    end
  end

  def handle_event("confirm_scraped", _, socket) do
    attrs = socket.assigns.scrape_result

    case Recipes.create(attrs) do
      {:ok, _recipe} ->
        {:noreply,
         socket
         |> assign(scrape_state: :idle, scrape_result: nil, scrape_url: "", error: nil)
         |> reload_recipes()}

      {:error, changeset} ->
        {:noreply, assign(socket, error: error_message(changeset))}
    end
  end

  def handle_event("discard_scraped", _, socket) do
    {:noreply, assign(socket, scrape_state: :idle, scrape_result: nil, error: nil)}
  end

  def handle_info({:scrape, url}, socket) do
    case Recipes.scrape_from_url(url) do
      {:ok, recipe} ->
        {:noreply,
         assign(socket, scrape_state: :idle, scrape_result: nil)
         |> reload_recipes()
         |> assign(selected: recipe)}

      {:error, reason} ->
        {:noreply,
         assign(socket, scrape_state: :idle, error: "Scrape failed: #{inspect(reason)}")}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-6">
      <div class="max-w-6xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Recipes</h1>
          <div class="flex gap-2">
            <button
              phx-click="new_recipe"
              class="px-4 py-2 bg-blue-600 rounded hover:bg-blue-500 text-sm"
            >
              + New
            </button>
          </div>
        </div>

        <%!-- Search & filters --%>
        <div class="mb-4 space-y-3">
          <input
            type="text"
            phx-change="search"
            name="query"
            value={@search}
            placeholder="Search recipes or ingredients…"
            class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm"
          />

          <div class="flex flex-wrap gap-2 text-sm">
            <%= for type <- @types do %>
              <button
                phx-click="filter_type"
                phx-value-type={type}
                class={[
                  "px-3 py-1 rounded-full border",
                  if(@filter_type == type,
                    do: "bg-blue-600 border-blue-600",
                    else: "border-gray-600 hover:border-gray-400"
                  )
                ]}
              >
                {type}
              </button>
            <% end %>
          </div>

          <div class="flex flex-wrap gap-2 text-sm">
            <%= for tag <- common_tags() do %>
              <button
                phx-click="filter_tag"
                phx-value-tag={tag}
                class={[
                  "px-3 py-1 rounded-full border",
                  if(tag in @filter_tags,
                    do: "bg-green-600 border-green-600",
                    else: "border-gray-600 hover:border-gray-400"
                  )
                ]}
              >
                {tag}
              </button>
            <% end %>
          </div>

          <div class="flex gap-4 text-sm text-gray-400">
            <span>Time:</span>
            <%= for t <- @time_filters do %>
              <button
                phx-click="filter_time"
                phx-value-max={t}
                class={
                  if @filter_max_min == t, do: "text-white font-semibold", else: "hover:text-white"
                }
              >
                {if t == :any, do: "Any", else: "≤#{t}m"}
              </button>
            <% end %>

            <span class="ml-6">Sort:</span>
            <%= for s <- @sorts do %>
              <button
                phx-click="sort"
                phx-value-by={s}
                class={if @sort == s, do: "text-white font-semibold", else: "hover:text-white"}
              >
                {sort_label(s)}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Scrape bar --%>
        <div class="mb-6 flex gap-2">
          <input
            type="text"
            phx-change="scrape_url_change"
            name="url"
            value={@scrape_url}
            placeholder="Paste recipe URL to scrape…"
            class="flex-1 bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm"
          />
          <button
            phx-click="scrape_submit"
            disabled={@scrape_state == :loading}
            class="px-4 py-2 bg-purple-600 rounded hover:bg-purple-500 disabled:opacity-40 text-sm"
          >
            {if @scrape_state == :loading, do: "Scraping…", else: "Scrape"}
          </button>
        </div>

        <%= if @error do %>
          <p class="text-red-400 text-sm mb-4">{@error}</p>
        <% end %>

        <div class="flex gap-6">
          <%!-- Recipe list --%>
          <div class="flex-1">
            <%= if @recipes == [] do %>
              <p class="text-gray-500 text-sm">No recipes yet.</p>
            <% else %>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for recipe <- @recipes do %>
                  <button
                    phx-click="select_recipe"
                    phx-value-id={recipe.id}
                    class={[
                      "text-left bg-gray-800 rounded-lg p-4 hover:bg-gray-700 border",
                      if(@selected && @selected.id == recipe.id,
                        do: "border-blue-500",
                        else: "border-transparent"
                      )
                    ]}
                  >
                    <%= if recipe.image_path do %>
                      <img src={recipe.image_path} class="w-full h-32 object-cover rounded mb-3" />
                    <% else %>
                      <div class="w-full h-32 bg-gray-700 rounded mb-3 flex items-center justify-center text-gray-500 text-xs">
                        No image
                      </div>
                    <% end %>
                    <p class="font-semibold text-sm">{recipe.title}</p>
                    <div class="flex flex-wrap gap-1 mt-2">
                      <%= for tag <- recipe.tags do %>
                        <span class="text-xs bg-gray-700 px-2 py-0.5 rounded-full">{tag.name}</span>
                      <% end %>
                    </div>
                    <p class="text-xs text-gray-400 mt-1">
                      {total_time(recipe)}
                    </p>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Detail / form panel --%>
          <%= if @form do %>
            <div class="w-80 bg-gray-800 rounded-lg p-4">
              <div class="flex justify-between mb-4">
                <h2 class="font-bold">{if @selected, do: "Edit Recipe", else: "New Recipe"}</h2>
                <button phx-click="close" class="text-gray-400 hover:text-white">✕</button>
              </div>
              <form phx-submit="save_recipe">
                <div class="space-y-3 text-sm">
                  <div>
                    <label class="block text-gray-400 mb-1">Title *</label>
                    <input
                      type="text"
                      name="recipe[title]"
                      value={@form[:title]}
                      required
                      class="w-full bg-gray-700 rounded px-2 py-1"
                    />
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-1">Type</label>
                    <select name="recipe[recipe_type]" class="w-full bg-gray-700 rounded px-2 py-1">
                      <%= for t <- [:meal, :component, :assembly] do %>
                        <option value={t} selected={@form[:recipe_type] == to_string(t)}>{t}</option>
                      <% end %>
                    </select>
                  </div>
                  <div class="flex gap-2">
                    <div class="flex-1">
                      <label class="block text-gray-400 mb-1">Prep (min)</label>
                      <input
                        type="number"
                        name="recipe[prep_time_minutes]"
                        value={@form[:prep_time_minutes]}
                        class="w-full bg-gray-700 rounded px-2 py-1"
                      />
                    </div>
                    <div class="flex-1">
                      <label class="block text-gray-400 mb-1">Cook (min)</label>
                      <input
                        type="number"
                        name="recipe[cook_time_minutes]"
                        value={@form[:cook_time_minutes]}
                        class="w-full bg-gray-700 rounded px-2 py-1"
                      />
                    </div>
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-1">Servings</label>
                    <input
                      type="number"
                      name="recipe[base_servings]"
                      value={@form[:base_servings]}
                      class="w-full bg-gray-700 rounded px-2 py-1"
                    />
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-1">Tags (comma-separated)</label>
                    <input
                      type="text"
                      name="recipe[tags]"
                      value={@form[:tags]}
                      placeholder="quick, batch, vegetarian"
                      class="w-full bg-gray-700 rounded px-2 py-1"
                    />
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-1">Source URL</label>
                    <input
                      type="text"
                      name="recipe[source_url]"
                      value={@form[:source_url]}
                      class="w-full bg-gray-700 rounded px-2 py-1"
                    />
                  </div>
                  <div>
                    <label class="block text-gray-400 mb-1">Instructions</label>
                    <textarea
                      name="recipe[instructions]"
                      rows="5"
                      class="w-full bg-gray-700 rounded px-2 py-1"
                    >{@form[:instructions]}</textarea>
                  </div>
                </div>
                <div class="flex gap-2 mt-4">
                  <button
                    type="submit"
                    class="flex-1 bg-blue-600 rounded py-2 hover:bg-blue-500 text-sm"
                  >
                    Save
                  </button>
                  <%= if @selected do %>
                    <button
                      type="button"
                      phx-click="delete_recipe"
                      class="px-3 py-2 bg-red-700 rounded hover:bg-red-600 text-sm"
                    >
                      Delete
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          <% end %>

          <%= if @selected && !@form do %>
            <div class="w-80 bg-gray-800 rounded-lg p-4">
              <div class="flex justify-between mb-4">
                <h2 class="font-bold">{@selected.title}</h2>
                <button phx-click="close" class="text-gray-400 hover:text-white">✕</button>
              </div>
              <%= if @selected.image_path do %>
                <img src={@selected.image_path} class="w-full h-40 object-cover rounded mb-3" />
              <% end %>
              <div class="text-sm text-gray-300 space-y-2">
                <p><span class="text-gray-500">Type:</span> {@selected.recipe_type}</p>
                <p><span class="text-gray-500">Time:</span> {total_time(@selected)}</p>
                <%= if @selected.base_servings do %>
                  <p><span class="text-gray-500">Servings:</span> {@selected.base_servings}</p>
                <% end %>
                <div class="flex flex-wrap gap-1">
                  <%= for tag <- @selected.tags do %>
                    <span class="text-xs bg-gray-700 px-2 py-0.5 rounded-full">{tag.name}</span>
                  <% end %>
                </div>
                <%= if @selected.instructions do %>
                  <div class="mt-3">
                    <p class="text-gray-500 mb-1">Instructions</p>
                    <p class="whitespace-pre-wrap text-xs">{@selected.instructions}</p>
                  </div>
                <% end %>
                <%= if @selected.source_url do %>
                  <a
                    href={@selected.source_url}
                    target="_blank"
                    class="text-blue-400 hover:underline text-xs block mt-2"
                  >
                    Source ↗
                  </a>
                <% end %>
              </div>
              <button
                phx-click="edit_recipe"
                class="mt-4 w-full bg-gray-700 rounded py-2 hover:bg-gray-600 text-sm"
              >
                Edit
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp reload(socket) do
    Recipes.list(
      tags: socket.assigns.filter_tags,
      type: socket.assigns.filter_type,
      max_minutes: socket.assigns.filter_max_min,
      sort: socket.assigns.sort
    )
  end

  defp reload_recipes(socket), do: assign(socket, recipes: reload(socket))

  defp blank_form do
    %{
      title: "",
      recipe_type: "meal",
      prep_time_minutes: nil,
      cook_time_minutes: nil,
      base_servings: nil,
      tags: "",
      source_url: "",
      instructions: ""
    }
  end

  defp recipe_to_form(recipe) do
    %{
      title: recipe.title,
      recipe_type: to_string(recipe.recipe_type),
      prep_time_minutes: recipe.prep_time_minutes,
      cook_time_minutes: recipe.cook_time_minutes,
      base_servings: recipe.base_servings,
      tags: recipe.tags |> Enum.map(& &1.name) |> Enum.join(", "),
      source_url: recipe.source_url,
      instructions: recipe.instructions
    }
  end

  defp parse_recipe_params(params) do
    tag_names =
      (params["tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    %{
      title: params["title"],
      recipe_type: String.to_existing_atom(params["recipe_type"] || "meal"),
      prep_time_minutes: parse_int(params["prep_time_minutes"]),
      cook_time_minutes: parse_int(params["cook_time_minutes"]),
      base_servings: parse_int(params["base_servings"]),
      source_url: params["source_url"],
      instructions: params["instructions"],
      tags: tag_names
    }
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_type("all"), do: :all
  defp parse_type(t), do: String.to_existing_atom(t)

  defp parse_time("any"), do: :any

  defp parse_time(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> :any
    end
  end

  defp parse_sort(s), do: String.to_existing_atom(s)

  defp total_time(recipe) do
    prep = recipe.prep_time_minutes || 0
    cook = recipe.cook_time_minutes || 0
    total = prep + cook
    if total > 0, do: "#{total} min", else: "—"
  end

  defp error_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp sort_label(:recently_added), do: "Recent"
  defp sort_label(:last_used), do: "Last used"
  defp sort_label(:alphabetical), do: "A–Z"

  defp common_tags, do: ["quick", "batch", "base-recipe", "vegetarian", "swedish", "asian"]
end
