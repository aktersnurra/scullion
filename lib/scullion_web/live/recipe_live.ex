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
       scrape_url: "",
       scrape_state: :idle,
       scrape_result: nil,
       image_extract_state: :idle,
       extracted_attrs: nil,
       selected: nil,
       detail_tab: "ingredients",
       form: nil,
       error: nil,
       sorts: @sorts,
       types: @types,
       time_filters: @time_filters
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

  def handle_event("new_recipe", _, socket) do
    {:noreply, assign(socket, form: blank_form(), extracted_attrs: nil, selected: nil, error: nil)}
  end

  def handle_event("save_recipe", %{"recipe" => params}, socket) do
    form_attrs = parse_recipe_params(params)

    attrs =
      case socket.assigns.extracted_attrs do
        nil -> form_attrs
        extracted ->
          require Logger
          Logger.debug("save_recipe extracted ingredients: #{inspect(extracted[:ingredients])}")
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
    {:noreply, assign(socket, selected: nil, form: nil, extracted_attrs: nil, error: nil)}
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, detail_tab: tab)}
  end

  def handle_event("scrape_submit", %{"url" => url}, socket) do
    url = String.trim(url)

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

  def handle_event("extract_from_images", _, socket) do
    entries = socket.assigns.uploads.recipe_images.entries

    if entries == [] do
      {:noreply, assign(socket, error: "Select at least one image")}
    else
      binaries =
        consume_uploaded_entries(socket, :recipe_images, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      send(self(), {:extract_images, binaries})
      {:noreply, assign(socket, image_extract_state: :loading, error: nil)}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :recipe_images, ref)}
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

        {:noreply, assign(socket, image_extract_state: :idle, form: form, extracted_attrs: attrs, selected: nil, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, image_extract_state: :idle, error: extract_error(reason))}
    end
  end

  def handle_info({:scrape, url}, socket) do
    case Recipes.scrape_from_url(url) do
      {:ok, recipe} ->
        {:noreply,
         assign(socket, scrape_state: :idle, scrape_result: nil)
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
    <.page max_width={:xl}>
      <.card class="mb-6">
        <header class="flex items-center justify-between gap-4 mb-5 pb-5 border-b border-[color:var(--hairline)]">
          <div>
            <h1 class="font-semibold text-[var(--text)]" style="font-size: var(--t-h1);">Recipes</h1>
            <p class="mt-0.5 text-[color:var(--muted)]" style="font-size: var(--t-meta);">{recipe_count_label(@recipes)}</p>
          </div>
          <.button variant={:primary} phx-click="new_recipe">
            <.icon name="hero-plus" class="size-4" /> New recipe
          </.button>
        </header>
        <form phx-change="search" class="relative">
          <.icon name="hero-magnifying-glass" class="size-5 absolute left-3.5 top-1/2 -translate-y-1/2 text-[color:var(--subtle)]" />
          <input
            type="text"
            name="query"
            value={@search}
            placeholder="Search recipes or ingredients…"
            class="w-full h-11 pl-10 pr-3 bg-[var(--surface)] rounded-[var(--r-lg)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
            style="font-size: var(--t-body);"
          />
        </form>

        <div class="mt-4 flex flex-wrap gap-2">
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

        <div class="mt-3 flex flex-wrap gap-2">
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

        <div class="mt-4 pt-4 border-t border-[color:var(--hairline)] flex flex-wrap items-center gap-x-6 gap-y-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
          <span class="text-[color:var(--subtle)] font-medium">Time</span>
          <button
            :for={t <- @time_filters}
            phx-click="filter_time"
            phx-value-max={t}
            class={[
              @filter_max_min == t && "text-[color:var(--accent)] font-medium",
              @filter_max_min != t && "hover:text-[var(--text)]"
            ]}
          >
            {if t == :any, do: "Any", else: "≤ #{t} min"}
          </button>

          <span class="ml-4 text-[color:var(--subtle)] font-medium">Sort</span>
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
      </.card>

      <.card class="mb-6">
        <h2 class="font-semibold mb-3" style="font-size: var(--t-h2);">Import</h2>
        <form class="flex gap-2 mb-3" phx-submit="scrape_submit">
          <input
            type="text"
            name="url"
            value={@scrape_url}
            placeholder="Paste recipe URL…"
            class="flex-1 h-11 px-3.5 bg-[var(--surface)] rounded-[var(--r-lg)] border border-[color:var(--border)] text-[var(--text)] placeholder:text-[color:var(--subtle)] focus:outline-none focus:border-[color:var(--accent)]"
            style="font-size: var(--t-body);"
          />
          <.button type="submit" variant={:primary} disabled={@scrape_state == :loading}>
            {if @scrape_state == :loading, do: "Importing…", else: "Import"}
          </.button>
        </form>

        <form phx-submit="extract_from_images" phx-change="validate" class="flex gap-2 items-start">
          <div class="flex-1">
            <label class="cursor-pointer flex items-center gap-2 h-11 px-3 border border-dashed border-[color:var(--border)] rounded-[var(--r-lg)] text-[color:var(--muted)] hover:border-[color:var(--subtle)] transition-colors" style="font-size: var(--t-meta);">
              <.live_file_input upload={@uploads.recipe_images} class="sr-only" />
              <.icon name="hero-camera" class="size-4 shrink-0" />
              <span>
                {if @uploads.recipe_images.entries == [],
                  do: "Upload photos (up to 10)…",
                  else: "#{length(@uploads.recipe_images.entries)} selected"}
              </span>
            </label>
            <div :for={entry <- @uploads.recipe_images.entries} class="flex items-center gap-2 mt-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
              <span class="flex-1 truncate">{entry.client_name}</span>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                      class="text-[color:var(--subtle)] hover:text-[color:var(--danger)]">✕</button>
            </div>
          </div>
          <.button
            type="submit"
            variant={:secondary}
            disabled={@image_extract_state == :loading or @uploads.recipe_images.entries == []}
          >
            {if @image_extract_state == :loading, do: "Extracting…", else: "Extract"}
          </.button>
        </form>
      </.card>

      <p :if={@error} class="mb-4 text-[color:var(--danger)]" style="font-size: var(--t-meta);">{@error}</p>

      <%= if @recipes == [] do %>
        <.card><.empty message="No recipes — add one or import from a URL" /></.card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
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

      <.drawer id="recipe-drawer" show={@selected != nil or @form != nil} on_close={JS.push("close")}>
        <%= cond do %>
          <% @form -> %>
            {render_form(assigns)}
          <% @selected -> %>
            {render_detail(assigns)}
          <% true -> %>
        <% end %>
      </.drawer>
    </.page>
    </Layouts.app>
    """
  end

  defp render_detail(assigns) do
    tabs = [
      %{id: "ingredients", label: "Ingredients"},
      %{id: "instructions", label: "Instructions"},
      %{id: "notes", label: "Notes"}
    ]
    assigns = assign(assigns, tabs: tabs)

    ~H"""
    <div>
      <button
        type="button"
        phx-click="close"
        class="inline-flex items-center gap-1 text-[color:var(--muted)] hover:text-[var(--text)] mb-3"
        style="font-size: var(--t-meta);"
      >
        <.icon name="hero-chevron-left" class="size-4" /> Back
      </button>

      <div :if={@selected.image_path} class="aspect-[4/3] w-full overflow-hidden rounded-[var(--r-xl)] bg-[color:var(--hairline)] mb-4">
        <img src={@selected.image_path} alt="" class="h-full w-full object-cover" />
      </div>

      <h2 class="font-semibold tracking-tight text-[var(--text)] mb-3" style="font-size: var(--t-h1);">
        {@selected.title}
      </h2>

      <div class="flex flex-wrap items-center gap-2 mb-5">
        <.chip :if={total_time(@selected) != "—"} tone={:neutral} icon="hero-clock">{total_time(@selected)}</.chip>
        <.chip :if={@selected.base_servings} tone={:neutral} icon="hero-user-group">{@selected.base_servings} servings</.chip>
        <.chip :for={tag <- Enum.take(@selected.tags, 4)} tone={:accent}>{tag.name}</.chip>
      </div>

      <.tabs items={@tabs} active={@detail_tab} />

      <div class="pt-4 mb-6">
        <%= cond do %>
          <% @detail_tab == "ingredients" and @selected.recipe_ingredients != [] -> %>
            <ul class="divide-y divide-[color:var(--hairline)]">
              <li :for={ri <- @selected.recipe_ingredients} class="flex items-center gap-3 py-2.5" style="font-size: var(--t-body);">
                <span class="size-1.5 rounded-full bg-[color:var(--accent)] shrink-0"></span>
                <span class="flex-1 text-[var(--text)]">{ri.ingredient.name}</span>
                <span :if={ri.quantity} class="shrink-0 text-[color:var(--muted)] tabular-nums" style="font-size: var(--t-meta);">
                  {ri.quantity} {ri.unit}
                </span>
              </li>
            </ul>
          <% @detail_tab == "ingredients" -> %>
            <p class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">No ingredients listed.</p>
          <% @detail_tab == "instructions" -> %>
            <%= if grouped_steps(@selected) != [] do %>
              <div :for={{phase, steps} <- grouped_steps(@selected)} class="mb-5">
                <h3 :if={phase} class="font-semibold mb-2" style="font-size: var(--t-h2);">{phase}</h3>
                <ol class="space-y-3">
                  <li :for={step <- steps} class="flex gap-3" style="font-size: var(--t-body);">
                    <span class="size-6 shrink-0 rounded-full bg-[color:var(--accent-soft)] text-[color:var(--accent-ink)] inline-flex items-center justify-center font-semibold" style="font-size: var(--t-meta);">{step["order"]}</span>
                    <div class="flex-1">
                      <span class="text-[var(--text)]">{step["action"]}</span>
                      <span :if={step["duration_minutes"]} class="ml-2 text-[color:var(--muted)]" style="font-size: var(--t-meta);">
                        {step["duration_minutes"]}m
                      </span>
                      <div :if={step["ingredients"] && step["ingredients"] != []} class="flex flex-wrap gap-1.5 mt-1.5">
                        <.chip :for={ing <- step["ingredients"]} tone={:accent}>{ing}</.chip>
                      </div>
                    </div>
                  </li>
                </ol>
              </div>
            <% else %>
              <p :if={@selected.instructions} class="whitespace-pre-wrap text-[var(--text)]" style="font-size: var(--t-body);">{@selected.instructions}</p>
              <p :if={!@selected.instructions} class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">No instructions yet.</p>
            <% end %>
          <% @detail_tab == "notes" -> %>
            <a :if={@selected.source_url} href={@selected.source_url} target="_blank"
               class="inline-flex items-center gap-1 text-[color:var(--accent)] hover:underline" style="font-size: var(--t-meta);">
              <.icon name="hero-link" class="size-4" /> Source
            </a>
            <p :if={!@selected.source_url} class="text-[color:var(--muted)]" style="font-size: var(--t-meta);">No notes.</p>
        <% end %>
      </div>

      <div class="flex gap-2 pt-4 border-t border-[color:var(--hairline)]">
        <.button variant={:secondary} phx-click="edit_recipe">Edit</.button>
        <.button variant={:danger} phx-click="delete_recipe">Delete</.button>
      </div>
    </div>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <div>
      <h2 class="font-semibold tracking-tight text-[var(--text)] mb-5" style="font-size: var(--t-h1);">
        {if @selected, do: "Edit recipe", else: "New recipe"}
      </h2>

      <form phx-submit="save_recipe" class="space-y-5">
        <.field name="recipe[title]" label="Title" value={@form[:title] || ""} required />

        <label class="block">
          <span class="block mb-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">Type</span>
          <select name="recipe[recipe_type]"
                  class="w-full bg-transparent border-0 border-b border-[color:var(--border)] py-2 text-[var(--text)] focus:outline-none focus:ring-0 focus:border-[color:var(--accent)]"
                  style="font-size: var(--t-body);">
            <option :for={t <- [:meal, :component, :assembly]} value={t} selected={@form[:recipe_type] == to_string(t)}>{t}</option>
          </select>
        </label>

        <div class="flex gap-4">
          <div class="flex-1">
            <.field name="recipe[prep_time_minutes]" label="Prep (min)" type="number" value={to_string_or_empty(@form[:prep_time_minutes])} />
          </div>
          <div class="flex-1">
            <.field name="recipe[cook_time_minutes]" label="Cook (min)" type="number" value={to_string_or_empty(@form[:cook_time_minutes])} />
          </div>
        </div>

        <.field name="recipe[base_servings]" label="Servings" type="number" value={to_string_or_empty(@form[:base_servings])} />
        <.field name="recipe[tags]" label="Tags" value={@form[:tags] || ""} placeholder="quick, batch, vegetarian" />
        <.field name="recipe[source_url]" label="Source URL" value={@form[:source_url] || ""} />

        <label class="block">
          <span class="block mb-1 text-[color:var(--muted)]" style="font-size: var(--t-meta);">Instructions</span>
          <textarea name="recipe[instructions]" rows="6"
                    class="w-full bg-transparent border border-[color:var(--border)] rounded-[var(--r-sm)] px-3 py-2 text-[var(--text)] focus:outline-none focus:ring-0 focus:border-[color:var(--accent)]"
                    style="font-size: var(--t-body);"
          >{@form[:instructions]}</textarea>
        </label>

        <div class="flex gap-2 pt-4 border-t border-[color:var(--border)]">
          <.button type="submit" variant={:primary}>Save</.button>
          <.button variant={:ghost} phx-click="close">Cancel</.button>
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

  defp extract_error(:provider_budget_exceeded), do: "Monthly LLM budget reached"
  defp extract_error(:rate_limited), do: "Too many requests — try again in a moment"
  defp extract_error({:openrouter_error, status, _}), do: "Extraction failed (API error #{status})"
  defp extract_error(_), do: "Could not extract recipe from the images"

  defp scrape_error({:http_error, status}) when is_integer(status),
    do: "Could not fetch page (HTTP #{status})"

  defp scrape_error({:req_error, _}),
    do: "Could not reach the URL — check your connection or the address"

  defp scrape_error(:not_implemented),
    do: "This site uses JavaScript to load content and cannot be scraped — try uploading a photo instead"

  defp scrape_error({:openrouter_error, status, _}),
    do: "Recipe extraction failed (API error #{status})"

  defp scrape_error(_),
    do: "Could not extract a recipe from this page"

  defp error_message(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end

  defp sort_label(:recently_added), do: "Recent"
  defp sort_label(:last_used), do: "Last used"
  defp sort_label(:alphabetical), do: "A–Z"

  defp recipe_count_label([]), do: nil
  defp recipe_count_label([_]), do: "1 recipe"
  defp recipe_count_label(list), do: "#{length(list)} recipes"

  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(v), do: to_string(v)

  defp common_tags, do: ["quick", "batch", "base-recipe", "vegetarian", "swedish", "asian"]
end
