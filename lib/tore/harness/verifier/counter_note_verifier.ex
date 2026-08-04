defmodule Tore.Harness.Verifier.CounterNoteVerifier do
  @moduledoc """
  Deterministic verifier for scan-generated counter note proposals. Pure: no
  writes, no model calls. Consumes the raw string-keyed map returned by the
  LLM, before it is inserted as a `CounterNote`.

  Checks:
    * `surface` is one of the scan-eligible surfaces
    * `kind` is one of the four scan kinds
    * `title` and `body` are present, non-blank, and within length limits
    * `confidence` is nil or a known level
    * `scoped_slot` is nil or a member of the week's slot-key set;
      `swap_suggestion` and `freezer_fallback` require a `scoped_slot`
    * `command` is nil or a non-blank string within length limits
    * `usual_item_missing` requires an `"item"` map with a non-blank `"name"`;
      other kinds must not carry `"item"`

  Returns `:ok` or `{:fail, code, repair}` for the first failing check. The
  repair action for scan proposals is `:reject` — invalid proposals are
  dropped before they ever reach the user.
  """

  @valid_surfaces ~w(home week groceries)
  @valid_kinds ~w(swap_suggestion freezer_fallback missing_ingredient usual_item_missing)
  @valid_confidences ~w(low medium high)
  @slot_required_kinds ~w(swap_suggestion freezer_fallback)

  @title_max 80
  @body_max 240
  @command_max 300

  @type fail_code ::
          :unknown_surface
          | :unknown_kind
          | :blank_title
          | :blank_body
          | :invalid_confidence
          | :invalid_slot
          | :missing_scoped_slot
          | :blank_command
          | :missing_item
          | :unexpected_item
  @type repair_action :: :reject

  @spec verify(map(), MapSet.t()) :: :ok | {:fail, fail_code(), repair_action()}
  def verify(proposal, slot_keys) when is_map(proposal) do
    with :ok <- check_surface(proposal),
         :ok <- check_kind(proposal),
         :ok <- check_title(proposal),
         :ok <- check_body(proposal),
         :ok <- check_confidence(proposal),
         :ok <- check_scoped_slot(proposal, slot_keys),
         :ok <- check_command(proposal),
         :ok <- check_item(proposal) do
      :ok
    end
  end

  defp check_surface(%{"surface" => surface}) when surface in @valid_surfaces, do: :ok
  defp check_surface(_), do: {:fail, :unknown_surface, :reject}

  defp check_kind(%{"kind" => kind}) when kind in @valid_kinds, do: :ok
  defp check_kind(_), do: {:fail, :unknown_kind, :reject}

  defp check_title(%{"title" => title}) do
    if blank?(title) or String.length(title) > @title_max do
      {:fail, :blank_title, :reject}
    else
      :ok
    end
  end

  defp check_title(_), do: {:fail, :blank_title, :reject}

  defp check_body(%{"body" => body}) do
    if blank?(body) or String.length(body) > @body_max do
      {:fail, :blank_body, :reject}
    else
      :ok
    end
  end

  defp check_body(_), do: {:fail, :blank_body, :reject}

  defp check_confidence(%{"confidence" => nil}), do: :ok
  defp check_confidence(%{"confidence" => c}) when c in @valid_confidences, do: :ok
  defp check_confidence(proposal), do: check_confidence_missing_key(proposal)

  defp check_confidence_missing_key(proposal) do
    if Map.has_key?(proposal, "confidence") do
      {:fail, :invalid_confidence, :reject}
    else
      :ok
    end
  end

  defp check_scoped_slot(%{"kind" => kind} = proposal, slot_keys) do
    scoped_slot = Map.get(proposal, "scoped_slot")

    cond do
      is_nil(scoped_slot) and kind in @slot_required_kinds ->
        {:fail, :missing_scoped_slot, :reject}

      is_nil(scoped_slot) ->
        :ok

      MapSet.member?(slot_keys, scoped_slot) ->
        :ok

      true ->
        {:fail, :invalid_slot, :reject}
    end
  end

  defp check_command(proposal) do
    case Map.get(proposal, "command") do
      nil ->
        :ok

      command when is_binary(command) ->
        if blank?(command) or String.length(command) > @command_max do
          {:fail, :blank_command, :reject}
        else
          :ok
        end

      _ ->
        {:fail, :blank_command, :reject}
    end
  end

  defp check_item(%{"kind" => "usual_item_missing"} = proposal) do
    case Map.get(proposal, "item") do
      %{"name" => name} when is_binary(name) ->
        if blank?(name), do: {:fail, :missing_item, :reject}, else: :ok

      _ ->
        {:fail, :missing_item, :reject}
    end
  end

  defp check_item(proposal) do
    if Map.has_key?(proposal, "item") do
      {:fail, :unexpected_item, :reject}
    else
      :ok
    end
  end

  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: true
end
