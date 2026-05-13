defmodule ScullionWeb.RecipeLive do
  use ScullionWeb, :live_view
  alias Scullion.Recipes

  @sorts [:recently_added, :last_used, :alphabetical]
  @types [:all, :meal, :component, :assembly]
  @time_filters [:any, 30, 45, 60]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       recipes: Recipes.list(),
       search: "",
       filter_tags: [],
       filter_type: :all,
       filter_max_min: :any,
       sort: :recently_added,
       scrape_state: :idle,
       image_extract_state: :idle,
       extracted_attrs: nil,
       selected: nil,
       form: nil,
       error: nil,
       sorts: @sorts,
       types: @types,
       time_filters: @time_filters,
       show_more_filters: false,
       ingredient_rows: [],
       show_recipe_menu: false
     )
     |> allow_upload(:recipe_images,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 10,
       max_file_size: 10_000_000
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

  def handle_event("toggle_more_filters", _, socket) do
    {:noreply, assign(socket, show_more_filters: !socket.assigns.show_more_filters)}
  end

  def handle_event("get_ideas", _, socket) do
    {:noreply, put_flash(socket, :info, gettext("Coming soon"))}
  end

  def handle_event("import_action", %{"url" => url}, socket) do
    cond do
      socket.assigns.uploads.recipe_images.entries != [] ->
        binaries =
          consume_uploaded_entries(socket, :recipe_images, fn %{path: path}, _entry ->
            {:ok, File.read!(path)}
          end)
        send(self(), {:extract_images, binaries})
        {:noreply, assign(socket, image_extract_state: :loading, error: nil)}

      String.trim(url) != "" ->
        send(self(), {:scrape, String.trim(url)})
        {:noreply, assign(socket, scrape_state: :loading, error: nil)}

      true ->
        {:noreply, assign(socket, error: gettext("Paste a URL or drop screenshots first"))}
    end
  end

  def handle_event("new_recipe", _, socket) do
    {:noreply, assign(socket, form: blank_form(), extracted_attrs: nil, selected: nil, error: nil, ingredient_rows: [])}
  end

  def handle_event("save_recipe", %{"recipe" => params} = payload, socket) do
    form_attrs = parse_recipe_params(Map.put(params, "ingredients", payload["ingredients"] || %{}))

    attrs =
      case socket.assigns.extracted_attrs do
        nil -> form_attrs
        extracted ->
          Map.merge(extracted, form_attrs)
      end

    case socket.assigns.selected do
      nil ->
        case Recipes.create(attrs) do
          {:ok, _recipe} ->
            {:noreply, socket |> assign(form: nil, extracted_attrs: nil, error: nil) |> reload_recipes()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: error_message(changeset))}
        end

      recipe ->
        case Recipes.update(recipe, attrs) do
          {:ok, _recipe} ->
            {:noreply, socket |> assign(form: nil, extracted_attrs: nil, selected: nil, error: nil) |> reload_recipes()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: error_message(changeset))}
        end
    end
  end

  def handle_event("select_recipe", %{"id" => id}, socket) do
    recipe = Recipes.get!(String.to_integer(id))
    {:noreply, assign(socket, selected: recipe, form: nil, error: nil, show_recipe_menu: false)}
  end

  def handle_event("edit_recipe", _, socket) do
    recipe = socket.assigns.selected
    rows = Enum.map(recipe.recipe_ingredients, fn ri ->
      %{
        name: ri.ingredient.name,
        quantity: to_string(ri.quantity || ""),
        unit: ri.unit || ""
      }
    end)
    {:noreply, assign(socket, form: recipe_to_form(recipe), ingredient_rows: rows, error: nil, show_recipe_menu: false)}
  end

  def handle_event("delete_recipe", _, socket) do
    case Recipes.delete(socket.assigns.selected) do
      {:ok, _} ->
        {:noreply, socket |> assign(selected: nil, form: nil) |> reload_recipes()}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Could not delete recipe"))}
    end
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, selected: nil, form: nil, extracted_attrs: nil, error: nil, show_recipe_menu: false)}
  end

  def handle_event("toggle_recipe_menu", _, socket) do
    {:noreply, assign(socket, show_recipe_menu: !socket.assigns.show_recipe_menu)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}


  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :recipe_images, ref)}
  end

  def handle_event("add_ingredient_row", _, socket) do
    rows = socket.assigns.ingredient_rows ++ [%{name: "", quantity: "", unit: ""}]
    {:noreply, assign(socket, ingredient_rows: rows)}
  end

  def handle_event("remove_ingredient_row", %{"index" => idx}, socket) do
    idx = String.to_integer(idx)
    rows = List.delete_at(socket.assigns.ingredient_rows, idx)
    {:noreply, assign(socket, ingredient_rows: rows)}
  end

  def handle_event("sync_ingredient", params, socket) do
    rows =
      (params["ingredients"] || %{})
      |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
      |> Enum.map(fn {_, ing} ->
        %{name: ing["name"] || "", quantity: ing["quantity"] || "", unit: ing["unit"] || ""}
      end)
    {:noreply, assign(socket, ingredient_rows: rows)}
  end



  def handle_info({:extract_images, binaries}, socket) do
    case Recipes.extract_from_images(binaries) do
      {:ok, attrs} ->
        form = %{
          title: attrs[:title] || "",
          recipe_type: "meal",
          prep_time_minutes: attrs[:prep_time_minutes],
          cook_time_minutes: attrs[:cook_time_minutes],
          base_servings: attrs[:base_servings],
          tags: (attrs[:tags] || []) |> Enum.join(", "),
          source_url: attrs[:source_url] || "",
          instructions: attrs[:instructions] || ""
        }

        rows = Enum.map(attrs[:ingredients] || [], fn ing ->
          %{
            name: to_string(Map.get(ing, :name) || Map.get(ing, "name") || ""),
            quantity: to_string(Map.get(ing, :quantity) || Map.get(ing, "quantity") || ""),
            unit: to_string(Map.get(ing, :unit) || Map.get(ing, "unit") || "")
          }
        end)
        {:noreply, assign(socket, image_extract_state: :idle, form: form, extracted_attrs: attrs, selected: nil, error: nil, ingredient_rows: rows)}

      {:error, reason} ->
        {:noreply, assign(socket, image_extract_state: :idle, error: extract_error(reason))}
    end
  end

  def handle_info({:scrape, url}, socket) do
    case Recipes.scrape_from_url(url) do
      {:ok, recipe} ->
        {:noreply,
         assign(socket, scrape_state: :idle)
         |> reload_recipes()
         |> assign(selected: recipe)}

      {:error, reason} ->
        {:noreply, assign(socket, scrape_state: :idle, error: scrape_error(reason))}
    end
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={assigns[:current_path] || "/recipes"}>
    <.page max_width={:md}>
      <.card class="mb-6">
        <header class="flex items-center justify-between gap-4 mb-5 pb-5 border-b border-[color:var(--hairline)]">
          <div>
            <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">{gettext("Recipes")}</h1>
            <p class="mt-0.5 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{recipe_count_label(@recipes)}</p>
          </div>
          <.button variant={:primary} phx-click="new_recipe">
            <.icon name="hero-plus" class="size-4" /> {gettext("New recipe")}
          </.button>
        </header>

        <div class="space-y-4">
          <%!-- Search --%>
          <form phx-change="search" class="relative">
            <.icon name="hero-magnifying-glass" class="size-5 absolute left-3.5 top-1/2 -translate-y-1/2 text-[color:var(--subtle)]" />
            <input
              type="text"
              name="query"
              value={@search}
              placeholder={gettext("Search recipes, ingredients, or meals…")}
              class="w-full h-12 pl-10 pr-3 bg-[color:var(--hairline)] rounded-[var(--r-lg)] border-2 border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
              style="font-size: var(--t-body);"
            />
          </form>

          <%!-- Type filters + More filters toggle --%>
          <div class="flex items-center justify-between gap-2">
            <div class="flex flex-wrap gap-2">
              <button
                :for={type <- @types}
                phx-click="filter_type"
                phx-value-type={type}
                class={[
                  "px-3 h-8 rounded-[var(--r-pill)] transition-colors capitalize",
                  @filter_type == type && "bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)]",
                  @filter_type != type && "bg-[color:var(--hairline)] text-[color:var(--muted)] hover:text-[var(--text)]"
                ]}
                style="font-size: var(--t-meta); font-weight: 500;"
              >
                {type}
              </button>
            </div>
            <button
              type="button"
              phx-click="toggle_more_filters"
              class={[
                "shrink-0 inline-flex items-center gap-1 px-3 h-8 rounded-[var(--r-pill)] transition-colors",
                @show_more_filters && "bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)]",
                !@show_more_filters && "text-[color:var(--muted)] hover:text-[var(--text)] hover:bg-[color:var(--hairline)]"
              ]}
              style="font-size: var(--t-meta); font-weight: 500;"
            >
              {gettext("More filters")}
              <.icon name={if @show_more_filters, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-3.5" />
            </button>
          </div>

          <%!-- Expanded filters --%>
          <div :if={@show_more_filters} class="space-y-3 pt-1">
            <div class="flex flex-wrap gap-2">
              <button
                :for={tag <- common_tags()}
                phx-click="filter_tag"
                phx-value-tag={tag}
                class={[
                  "px-3 h-7 rounded-[var(--r-pill)] transition-colors",
                  tag in @filter_tags && "bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)]",
                  tag not in @filter_tags && "text-[color:var(--muted)] hover:text-[var(--text)]"
                ]}
                style="font-size: var(--t-meta);"
              >
                {tag}
              </button>
            </div>
            <div class="flex flex-wrap items-center gap-x-6 gap-y-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              <span class="text-[color:var(--subtle)] font-medium">{gettext("Time")}</span>
              <button
                :for={t <- @time_filters}
                phx-click="filter_time"
                phx-value-max={t}
                class={[
                  @filter_max_min == t && "text-[color:var(--accent)] font-medium",
                  @filter_max_min != t && "hover:text-[var(--text)]"
                ]}
              >
                {if t == :any, do: gettext("Any"), else: gettext("≤ %{n} min", n: t)}
              </button>
              <span class="ml-4 text-[color:var(--subtle)] font-medium">{gettext("Sort")}</span>
              <button
                :for={s <- @sorts}
                phx-click="sort"
                phx-value-by={s}
                class={[
                  @sort == s && "text-[color:var(--accent)] font-medium",
                  @sort != s && "hover:text-[var(--text)]"
                ]}
              >
                {sort_label(s)}
              </button>
            </div>
          </div>

          <%!-- Hero prompt --%>
          <div class="flex items-center justify-between gap-4 px-4 py-3 rounded-[var(--r-lg)] bg-[color:var(--accent-soft)]/40">
            <div class="flex items-start gap-3">
              <.icon name="hero-sparkles" class="size-5 text-[color:var(--accent)] shrink-0 mt-0.5" />
              <div>
                <p class="font-semibold text-[var(--text)]" style="font-size: var(--t-meta);">{gettext("What can we cook tonight?")}</p>
                <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Get ideas based on your pantry and this week's deals")}</p>
              </div>
            </div>
            <.button variant={:secondary} phx-click="get_ideas">{gettext("Get ideas")}</.button>
          </div>

          <%!-- Import row --%>
          <form phx-submit="import_action" phx-change="validate" class="space-y-2">
            <div class="flex gap-2">
              <div class="relative flex-1">
                <input
                  type="text"
                  name="url"
                  value=""
                  placeholder={gettext("Paste a recipe URL or drop screenshots…")}
                  class="w-full h-11 px-3.5 bg-[var(--surface)] rounded-[var(--r-lg)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)] pr-10"
                  style="font-size: var(--t-body);"
                />
                <label class="absolute right-3 top-1/2 -translate-y-1/2 cursor-pointer text-[color:var(--subtle)] hover:text-[color:var(--muted)]">
                  <.live_file_input upload={@uploads.recipe_images} class="sr-only" />
                  <.icon name="hero-camera" class="size-5" />
                </label>
              </div>
              <.button
                type="submit"
                variant={:primary}
                disabled={@scrape_state == :loading or @image_extract_state == :loading}
              >
                {cond do
                  @scrape_state == :loading -> gettext("Importing…")
                  @image_extract_state == :loading -> gettext("Extracting…")
                  true -> gettext("Import")
                end}
              </.button>
            </div>
            <div :for={entry <- @uploads.recipe_images.entries} class="flex items-center gap-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              <span class="flex-1 truncate">{entry.client_name}</span>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                      class="text-[color:var(--subtle)] hover:text-[color:var(--danger)]">✕</button>
            </div>
          </form>
        </div>
      </.card>

      <p :if={@error} class="mb-4 text-[color:var(--danger)]" style="font-size: var(--t-meta);">{@error}</p>

      <%= if @recipes == [] do %>
        <.card><.empty message={gettext("No recipes — add one or import from a URL")} /></.card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <button
            :for={recipe <- @recipes}
            type="button"
            phx-click="select_recipe"
            phx-value-id={recipe.id}
            class={[
              "group block text-left bg-[var(--surface)] rounded-[var(--r-xl)] overflow-hidden border transition-all shadow-[0_1px_2px_rgba(17,24,39,0.04)] hover:shadow-[0_4px_16px_rgba(17,24,39,0.08)]",
              @selected && @selected.id == recipe.id && "border-[color:var(--accent)]",
              !(@selected && @selected.id == recipe.id) && "border-[color:var(--border)]"
            ]}
          >
            <div class="aspect-[4/3] w-full bg-[color:var(--hairline)] flex items-center justify-center text-[color:var(--subtle)]">
              <img :if={recipe.image_path} src={recipe.image_path} alt="" class="h-full w-full object-cover transition-transform group-hover:scale-[1.02]" />
              <.icon :if={!recipe.image_path} name="hero-photo" class="size-10" />
            </div>
            <div class="p-4">
              <p class="font-semibold text-[var(--text)] truncate" style="font-size: var(--t-body);">{recipe.title}</p>
              <div class="mt-1.5 flex items-center gap-3 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                <span class="inline-flex items-center gap-1"><.icon name="hero-clock" class="size-3.5" /> {total_time(recipe)}</span>
              </div>
              <div :if={recipe.tags != []} class="flex flex-wrap gap-1.5 mt-3">
                <.chip :for={tag <- Enum.take(recipe.tags, 3)} tone={:accent}>{tag.name}</.chip>
              </div>
            </div>
          </button>
        </div>
      <% end %>

      <div :if={@selected != nil or @form != nil} class="fixed inset-0 z-50 flex items-end md:items-center justify-center p-4"
           phx-window-keydown="close" phx-key="Escape">
        <div class="absolute inset-0 bg-black/30" phx-click="close"></div>
        <div class="relative w-full md:max-w-lg bg-[var(--surface)] rounded-[var(--r-xl)] shadow-[0_8px_32px_rgba(17,24,39,0.16)] overflow-y-auto" style="max-height: 90vh;">
          <%= cond do %>
            <% @form -> %>
              <div class="p-6">{render_form(assigns)}</div>
            <% @selected -> %>
              {render_detail(assigns)}
            <% true -> %>
          <% end %>
        </div>
      </div>
    </.page>
    </Layouts.app>
    """
  end

  defp render_detail(assigns) do
    ~H"""
    <div>
      <%!-- Hero image --%>
      <div class={["w-full bg-[color:var(--hairline)] relative", @selected.image_path && "aspect-[4/3]"]}>
        <img :if={@selected.image_path} src={@selected.image_path} alt="" class="h-full w-full object-cover" />
        <%!-- Top bar: close left, actions right --%>
        <div class={["flex items-center justify-between p-3", @selected.image_path && "absolute top-0 inset-x-0"]}>
          <button type="button" phx-click="close"
            class={["size-9 inline-flex items-center justify-center rounded-[var(--r-md)]",
              @selected.image_path && "bg-black/40 text-white hover:bg-black/60",
              !@selected.image_path && "text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"]}>
            <.icon name="hero-x-mark" class="size-5" />
          </button>
          <div class="relative" id="recipe-actions">
            <button type="button" phx-click="toggle_recipe_menu"
              class={["size-9 inline-flex items-center justify-center rounded-[var(--r-md)]",
                @selected.image_path && "bg-black/40 text-white hover:bg-black/60",
                !@selected.image_path && "text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"]}>
              <.icon name="hero-ellipsis-horizontal" class="size-5" />
            </button>
            <div :if={@show_recipe_menu} class="absolute right-0 top-10 w-36 bg-[var(--surface)] rounded-[var(--r-lg)] shadow-[var(--shadow-pop)] border border-[color:var(--border)] overflow-hidden z-10">
              <button type="button" phx-click="edit_recipe"
                class="w-full text-left px-4 py-2.5 text-[var(--text)] hover:bg-[color:var(--hairline)]"
                style="font-size: var(--t-meta);">{gettext("Edit")}</button>
              <button type="button" phx-click="delete_recipe"
                class="w-full text-left px-4 py-2.5 text-[color:var(--danger)] hover:bg-[color:var(--hairline)]"
                style="font-size: var(--t-meta);">{gettext("Delete")}</button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Content --%>
      <div class="p-6 space-y-6">
        <%!-- Title + meta --%>
        <div>
          <h2 class="font-semibold tracking-tight text-[var(--text)] mb-3" style="font-size: var(--t-h1); line-height: 1.2;">
            {@selected.title}
          </h2>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
            <span :if={total_time(@selected) != "—"} class="inline-flex items-center gap-1.5">
              <.icon name="hero-clock" class="size-4" /> {total_time(@selected)}
            </span>
            <span :if={@selected.base_servings} class="inline-flex items-center gap-1.5">
              <.icon name="hero-user-group" class="size-4" /> {gettext("%{n} servings", n: @selected.base_servings)}
            </span>
          </div>
          <div :if={@selected.tags != []} class="flex flex-wrap gap-1.5 mt-3">
            <.chip :for={tag <- @selected.tags} tone={:accent}>{tag.name}</.chip>
          </div>
        </div>

        <%!-- Ingredients --%>
        <div :if={@selected.recipe_ingredients != []}>
          <h3 class="font-semibold text-[var(--text)] mb-3" style="font-size: var(--t-h2);">{gettext("Ingredients")}</h3>
          <ul class="space-y-2">
            <li :for={ri <- @selected.recipe_ingredients} class="flex items-baseline gap-3" style="font-size: var(--t-body);">
              <span class="size-1.5 rounded-full bg-[color:var(--accent)] shrink-0 mt-2"></span>
              <span class="flex-1 text-[var(--text)]">{ri.ingredient.name}</span>
              <span :if={ri.quantity} class="shrink-0 text-[color:var(--muted)] tabular-nums" style="font-size: var(--t-meta);">
                {ri.quantity}{if ri.unit && ri.unit != "", do: " #{ri.unit}"}
              </span>
            </li>
          </ul>
        </div>

        <%!-- Instructions --%>
        <div :if={@selected.steps || @selected.instructions}>
          <h3 class="font-semibold text-[var(--text)] mb-3" style="font-size: var(--t-h2);">{gettext("Instructions")}</h3>
          <%= if grouped_steps(@selected) != [] do %>
            <div :for={{phase, steps} <- grouped_steps(@selected)} class="mb-5 last:mb-0">
              <h4 :if={phase} class="font-medium text-[color:var(--muted)] mb-2 uppercase tracking-wide" style="font-size: var(--t-micro);">{phase}</h4>
              <ol class="space-y-4">
                <li :for={step <- steps} class="flex gap-3" style="font-size: var(--t-body);">
                  <span class="size-6 shrink-0 rounded-full bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)] inline-flex items-center justify-center font-semibold mt-0.5" style="font-size: var(--t-micro);">{step["order"]}</span>
                  <div class="flex-1 pt-0.5">
                    <span class="text-[var(--text)]">{step["action"]}</span>
                    <span :if={step["duration_minutes"]} class="ml-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{step["duration_minutes"]}m</span>
                  </div>
                </li>
              </ol>
            </div>
          <% else %>
            <p class="whitespace-pre-wrap text-[var(--text)] leading-relaxed" style="font-size: var(--t-body);">{@selected.instructions}</p>
          <% end %>
        </div>

        <%!-- Source --%>
        <div :if={@selected.source_url}>
          <a href={@selected.source_url} target="_blank"
            class="inline-flex items-center gap-1.5 text-[color:var(--muted)] hover:text-[var(--text)]"
            style="font-size: var(--t-meta);">
            <.icon name="hero-link" class="size-4" /> {gettext("Original recipe")}
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-5">
        <h2 class="font-semibold tracking-tight text-[var(--text)]" style="font-size: var(--t-h1);">
          {if @selected, do: gettext("Edit recipe"), else: gettext("New recipe")}
        </h2>
        <button
          type="button"
          phx-click="close"
          class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--muted)] hover:bg-[color:var(--hairline)]"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <form phx-submit="save_recipe" class="space-y-5">
        <.field name="recipe[title]" label={gettext("Title")} value={@form[:title] || ""} required />

        <label class="block">
          <span class="block mb-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Type")}</span>
          <select name="recipe[recipe_type]"
                  class="w-full bg-transparent border-0 border-b border-[color:var(--border)] py-2 text-[var(--text)] focus:outline-none focus:ring-0 focus:border-[color:var(--accent)]"
                  style="font-size: var(--t-body);">
            <option :for={t <- [:meal, :component, :assembly]} value={t} selected={@form[:recipe_type] == to_string(t)}>{t}</option>
          </select>
        </label>

        <div class="flex gap-4">
          <div class="flex-1">
            <.field name="recipe[prep_time_minutes]" label={gettext("Prep (min)")} type="number" value={to_string_or_empty(@form[:prep_time_minutes])} />
          </div>
          <div class="flex-1">
            <.field name="recipe[cook_time_minutes]" label={gettext("Cook (min)")} type="number" value={to_string_or_empty(@form[:cook_time_minutes])} />
          </div>
        </div>

        <.field name="recipe[base_servings]" label={gettext("Servings")} type="number" value={to_string_or_empty(@form[:base_servings])} />
        <.field name="recipe[tags]" label={gettext("Tags")} value={@form[:tags] || ""} placeholder="quick, batch, vegetarian" />
        <div>
          <span class="block mb-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Ingredients")}</span>
          <div class="space-y-2">
            <div :for={{row, idx} <- Enum.with_index(@ingredient_rows)} class="flex items-center gap-2">
              <input
                type="text"
                name={"ingredients[#{idx}][name]"}
                value={row.name}
                placeholder={gettext("Ingredient")}
                phx-change="sync_ingredient"
                phx-value-index={idx}
                phx-debounce="blur"
                class="flex-1 h-10 px-3 bg-[var(--surface)] rounded-[var(--r-md)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-body);"
              />
              <input
                type="text"
                name={"ingredients[#{idx}][quantity]"}
                value={row.quantity}
                placeholder={gettext("Qty")}
                phx-change="sync_ingredient"
                phx-value-index={idx}
                phx-debounce="blur"
                class="w-20 h-10 px-3 bg-[var(--surface)] rounded-[var(--r-md)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-body);"
              />
              <input
                type="text"
                name={"ingredients[#{idx}][unit]"}
                value={row.unit}
                placeholder={gettext("Unit")}
                phx-change="sync_ingredient"
                phx-value-index={idx}
                phx-debounce="blur"
                class="w-24 h-10 px-3 bg-[var(--surface)] rounded-[var(--r-md)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
                style="font-size: var(--t-body);"
              />
              <button
                type="button"
                phx-click="remove_ingredient_row"
                phx-value-index={idx}
                class="size-9 inline-flex items-center justify-center rounded-[var(--r-md)] text-[color:var(--subtle)] hover:text-[color:var(--danger)] hover:bg-[color:var(--hairline)]"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
          <button
            type="button"
            phx-click="add_ingredient_row"
            class="mt-2 inline-flex items-center gap-1 text-[color:var(--accent)] hover:underline"
            style="font-size: var(--t-meta); font-weight: 500;"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Add ingredient")}
          </button>
        </div>
        <.field name="recipe[source_url]" label={gettext("Source URL")} value={@form[:source_url] || ""} />

        <label class="block">
          <span class="block mb-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{gettext("Instructions")}</span>
          <textarea name="recipe[instructions]" rows="6"
                    class="w-full bg-transparent border border-[color:var(--border)] rounded-[var(--r-sm)] px-3 py-2 text-[var(--text)] focus:outline-none focus:ring-0 focus:border-[color:var(--accent)]"
                    style="font-size: var(--t-body);"
          >{@form[:instructions]}</textarea>
        </label>

        <div class="flex gap-2 pt-4 border-t border-[color:var(--border)]">
          <.button type="submit" variant={:primary}>{gettext("Save")}</.button>
          <.button variant={:ghost} phx-click="close">{gettext("Cancel")}</.button>
        </div>
      </form>
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

    ingredients =
      (params["ingredients"] || %{})
      |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
      |> Enum.map(fn {_, ing} ->
        %{
          name: String.trim(ing["name"] || ""),
          quantity: ing["quantity"],
          unit: ing["unit"]
        }
      end)
      |> Enum.reject(fn %{name: name} -> name == "" end)

    %{
      title: params["title"],
      recipe_type: String.to_existing_atom(params["recipe_type"] || "meal"),
      prep_time_minutes: parse_int(params["prep_time_minutes"]),
      cook_time_minutes: parse_int(params["cook_time_minutes"]),
      base_servings: parse_int(params["base_servings"]),
      source_url: params["source_url"],
      instructions: params["instructions"],
      tags: tag_names,
      ingredients: ingredients
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

  defp grouped_steps(recipe) do
    case recipe.steps do
      nil -> []
      json ->
        Jason.decode!(json)
        |> Enum.sort_by(& &1["order"])
        |> Enum.chunk_by(& &1["phase"])
        |> Enum.map(fn steps -> {hd(steps)["phase"], steps} end)
    end
  end

  defp total_time(recipe) do
    prep = recipe.prep_time_minutes || 0
    cook = recipe.cook_time_minutes || 0
    total = prep + cook
    if total > 0, do: "#{total} min", else: "—"
  end

  defp extract_error(:provider_budget_exceeded), do: gettext("Monthly LLM budget reached")
  defp extract_error(:rate_limited), do: gettext("Too many requests — try again in a moment")
  defp extract_error({:openrouter_error, status, _}), do: gettext("Extraction failed (API error %{status})", status: status)
  defp extract_error(_), do: gettext("Could not extract recipe from the images")

  defp scrape_error({:http_error, status}) when is_integer(status),
    do: gettext("Could not fetch page (HTTP %{status})", status: status)

  defp scrape_error({:req_error, _}),
    do: gettext("Could not reach the URL — check your connection or the address")

  defp scrape_error(:not_implemented),
    do: gettext("This site uses JavaScript to load content and cannot be scraped — try uploading a photo instead")

  defp scrape_error({:openrouter_error, status, _}),
    do: gettext("Recipe extraction failed (API error %{status})", status: status)

  defp scrape_error(_),
    do: gettext("Could not extract a recipe from this page")

  defp error_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp sort_label(:recently_added), do: gettext("Recent")
  defp sort_label(:last_used), do: gettext("Last used")
  defp sort_label(:alphabetical), do: gettext("A–Z")

  defp recipe_count_label([]), do: nil
  defp recipe_count_label([_]), do: gettext("1 recipe")
  defp recipe_count_label(list), do: gettext("%{n} recipes", n: length(list))

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(v), do: to_string(v)

  defp common_tags, do: ["quick", "batch", "base-recipe", "vegetarian", "swedish", "asian"]
end
