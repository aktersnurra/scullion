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
    <div class="p-6">
      <div class="max-w-6xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-xl font-semibold text-gray-900">Recipes</h1>
          <button phx-click="new_recipe" class="px-4 py-2 bg-gray-900 hover:bg-gray-700 text-white rounded-lg text-sm font-medium">
            + New recipe
          </button>
        </div>

        <%!-- Search & filters --%>
        <div class="mb-5 space-y-3">
          <input
            type="text"
            phx-change="search"
            name="query"
            value={@search}
            placeholder="Search recipes or ingredients…"
            class="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-green-500"
          />

          <div class="flex flex-wrap gap-2 text-sm">
            <%= for type <- @types do %>
              <button
                phx-click="filter_type"
                phx-value-type={type}
                class={[
                  "px-3 py-1 rounded-full border text-sm",
                  if(@filter_type == type,
                    do: "bg-gray-900 border-gray-900 text-white",
                    else: "border-gray-200 text-gray-500 hover:border-gray-400"
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
                  "px-3 py-1 rounded-full border text-sm",
                  if(tag in @filter_tags,
                    do: "bg-green-600 border-green-600 text-white",
                    else: "border-gray-200 text-gray-500 hover:border-gray-400"
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
                class={if @filter_max_min == t, do: "text-gray-900 font-semibold", else: "hover:text-gray-700"}
              >
                {if t == :any, do: "Any", else: "≤#{t}m"}
              </button>
            <% end %>

            <span class="ml-4">Sort:</span>
            <%= for s <- @sorts do %>
              <button
                phx-click="sort"
                phx-value-by={s}
                class={if @sort == s, do: "text-gray-900 font-semibold", else: "hover:text-gray-700"}
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
            placeholder="Paste recipe URL to import…"
            class="flex-1 border border-gray-200 rounded-xl px-4 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-green-500"
          />
          <button
            phx-click="scrape_submit"
            disabled={@scrape_state == :loading}
            class="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-xl text-sm disabled:opacity-40"
          >
            {if @scrape_state == :loading, do: "Importing…", else: "Import"}
          </button>
        </div>

        <%= if @error do %>
          <p class="text-red-500 text-sm mb-4 bg-red-50 border border-red-100 rounded-lg px-3 py-2">{@error}</p>
        <% end %>

        <div class="flex gap-6">
          <%!-- Recipe grid --%>
          <div class="flex-1">
            <%= if @recipes == [] do %>
              <div class="text-center py-20 text-gray-400">
                <p class="text-sm">No recipes yet — add one or import from a URL.</p>
              </div>
            <% else %>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for recipe <- @recipes do %>
                  <button
                    phx-click="select_recipe"
                    phx-value-id={recipe.id}
                    class={[
                      "text-left bg-white rounded-xl border overflow-hidden hover:shadow-md transition-shadow",
                      if(@selected && @selected.id == recipe.id,
                        do: "border-green-500 ring-1 ring-green-500",
                        else: "border-gray-100"
                      )
                    ]}
                  >
                    <%= if recipe.image_path do %>
                      <img src={recipe.image_path} class="w-full h-36 object-cover" />
                    <% else %>
                      <div class="w-full h-36 bg-gray-100 flex items-center justify-center text-gray-300 text-xs">
                        No image
                      </div>
                    <% end %>
                    <div class="p-3">
                      <p class="font-medium text-sm text-gray-900">{recipe.title}</p>
                      <div class="flex flex-wrap gap-1 mt-2">
                        <%= for tag <- recipe.tags do %>
                          <span class="text-xs bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">{tag.name}</span>
                        <% end %>
                      </div>
                      <p class="text-xs text-gray-400 mt-1.5">{total_time(recipe)}</p>
                    </div>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Detail / form panel --%>
          <%= if @form do %>
            <div class="w-80 bg-white rounded-xl border border-gray-100 p-5 shrink-0">
              <div class="flex justify-between items-center mb-4">
                <h2 class="font-semibold text-gray-900">{if @selected, do: "Edit Recipe", else: "New Recipe"}</h2>
                <button phx-click="close" class="text-gray-400 hover:text-gray-600">✕</button>
              </div>
              <form phx-submit="save_recipe">
                <div class="space-y-3 text-sm">
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Title *</label>
                    <input type="text" name="recipe[title]" value={@form[:title]} required
                           class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Type</label>
                    <select name="recipe[recipe_type]" class="w-full border border-gray-200 rounded-lg px-2 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-green-500">
                      <%= for t <- [:meal, :component, :assembly] do %>
                        <option value={t} selected={@form[:recipe_type] == to_string(t)}>{t}</option>
                      <% end %>
                    </select>
                  </div>
                  <div class="flex gap-2">
                    <div class="flex-1">
                      <label class="block text-xs text-gray-500 mb-1">Prep (min)</label>
                      <input type="number" name="recipe[prep_time_minutes]" value={@form[:prep_time_minutes]}
                             class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                    </div>
                    <div class="flex-1">
                      <label class="block text-xs text-gray-500 mb-1">Cook (min)</label>
                      <input type="number" name="recipe[cook_time_minutes]" value={@form[:cook_time_minutes]}
                             class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                    </div>
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Servings</label>
                    <input type="number" name="recipe[base_servings]" value={@form[:base_servings]}
                           class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Tags (comma-separated)</label>
                    <input type="text" name="recipe[tags]" value={@form[:tags]} placeholder="quick, batch, vegetarian"
                           class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Source URL</label>
                    <input type="text" name="recipe[source_url]" value={@form[:source_url]}
                           class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500" />
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500 mb-1">Instructions</label>
                    <textarea name="recipe[instructions]" rows="5"
                              class="w-full border border-gray-200 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-green-500">{@form[:instructions]}</textarea>
                  </div>
                </div>
                <div class="flex gap-2 mt-4">
                  <button type="submit" class="flex-1 bg-green-600 hover:bg-green-700 text-white rounded-lg py-2 text-sm font-medium">
                    Save
                  </button>
                  <%= if @selected do %>
                    <button type="button" phx-click="delete_recipe"
                            class="px-3 py-2 border border-red-200 text-red-500 hover:bg-red-50 rounded-lg text-sm">
                      Delete
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          <% end %>

          <%= if @selected && !@form do %>
            <div class="w-80 bg-white rounded-xl border border-gray-100 overflow-hidden shrink-0">
              <div class="flex justify-between items-center p-4 pb-3">
                <h2 class="font-semibold text-gray-900 text-sm">{@selected.title}</h2>
                <button phx-click="close" class="text-gray-400 hover:text-gray-600">✕</button>
              </div>
              <%= if @selected.image_path do %>
                <img src={@selected.image_path} class="w-full h-44 object-cover" />
              <% end %>
              <div class="p-4 text-sm text-gray-600 space-y-2">
                <p><span class="text-gray-400">Type:</span> {@selected.recipe_type}</p>
                <p><span class="text-gray-400">Time:</span> {total_time(@selected)}</p>
                <%= if @selected.base_servings do %>
                  <p><span class="text-gray-400">Servings:</span> {@selected.base_servings}</p>
                <% end %>
                <div class="flex flex-wrap gap-1">
                  <%= for tag <- @selected.tags do %>
                    <span class="text-xs bg-gray-100 text-gray-500 px-2 py-0.5 rounded-full">{tag.name}</span>
                  <% end %>
                </div>
                <%= if @selected.instructions do %>
                  <div class="mt-2 pt-2 border-t border-gray-100">
                    <p class="text-xs text-gray-400 mb-1">Instructions</p>
                    <p class="whitespace-pre-wrap text-xs text-gray-600">{@selected.instructions}</p>
                  </div>
                <% end %>
                <%= if @selected.source_url do %>
                  <a href={@selected.source_url} target="_blank"
                     class="text-green-600 hover:underline text-xs block mt-2">
                    Source ↗
                  </a>
                <% end %>
              </div>
              <div class="px-4 pb-4">
                <button phx-click="edit_recipe" class="w-full border border-gray-200 rounded-lg py-2 text-sm hover:bg-gray-50 text-gray-700">
                  Edit
                </button>
              </div>
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
