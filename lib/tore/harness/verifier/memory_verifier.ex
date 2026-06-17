defmodule Tore.Harness.Verifier.MemoryVerifier do
  @moduledoc """
  Deterministic verifier for `MemoryUpdate`. Pure: no writes, no model calls.

  Checks:
    * every added insight has a valid `kind`, body, and confidence in [0, 1]
    * every added insight has an `evidence` list (may be empty)
    * total active count after apply (added + unchanged) does not exceed
      `:max_active`

  Returns `:ok` or `{:fail, code, repair}` for the first failing check. The
  repair action for memory runs is `:reject` — there is no in-line edit path
  because the user does not see proposed insights before they commit; the
  synthesis either lands or fails the run.
  """

  alias Tore.Harness.Artifact.MemoryUpdate

  @valid_kinds ~w[skip_pattern cascade_success time_preference cuisine_fatigue variety_win]

  @type fail_code ::
          :invalid_insight_kind
          | :invalid_confidence
          | :missing_body
          | :missing_evidence
          | :too_many_active
  @type repair_action :: :reject
  @type ctx :: %{max_active: pos_integer()}

  @spec verify(MemoryUpdate.t(), ctx()) :: :ok | {:fail, fail_code(), repair_action()}
  def verify(%MemoryUpdate{} = update, ctx) do
    with :ok <- check_kinds(update.added),
         :ok <- check_bodies(update.added),
         :ok <- check_confidence(update.added),
         :ok <- check_evidence(update.added),
         :ok <- check_active_count(update, ctx) do
      :ok
    end
  end

  defp check_kinds(added) do
    case Enum.find(added, fn ins -> ins.kind not in @valid_kinds end) do
      nil -> :ok
      _ -> {:fail, :invalid_insight_kind, :reject}
    end
  end

  defp check_bodies(added) do
    case Enum.find(added, fn ins -> not is_binary(ins.body) or ins.body == "" end) do
      nil -> :ok
      _ -> {:fail, :missing_body, :reject}
    end
  end

  defp check_confidence(added) do
    case Enum.find(added, fn ins -> not in_unit_interval?(ins.confidence) end) do
      nil -> :ok
      _ -> {:fail, :invalid_confidence, :reject}
    end
  end

  defp check_evidence(added) do
    case Enum.find(added, fn ins -> not is_list(ins.evidence) end) do
      nil -> :ok
      _ -> {:fail, :missing_evidence, :reject}
    end
  end

  defp check_active_count(%MemoryUpdate{added: a, unchanged: u}, %{max_active: max}) do
    if length(a) + length(u) > max do
      {:fail, :too_many_active, :reject}
    else
      :ok
    end
  end

  defp in_unit_interval?(n) when is_number(n), do: n >= 0.0 and n <= 1.0
  defp in_unit_interval?(_), do: false
end
