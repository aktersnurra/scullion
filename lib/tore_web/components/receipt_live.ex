defmodule ToreWeb.Components.ReceiptLive do
  use ToreWeb, :live_component

  alias Tore.Harness.Run.State
  alias Tore.Harness.Artifact
  alias Tore.Harness.Artifact.RunSummary

  @impl true
  def update(%{run: run} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:header_text, header_for(run))
     |> assign(:body_html, body(run))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-2xl border border-[color:var(--hairline)] bg-[color:var(--surface-raised)] p-4">
      <p class="text-[10px] font-semibold text-[color:var(--accent)] uppercase tracking-widest mb-1">
        {@header_text}
      </p>
      <div class="text-sm text-[color:var(--ink)]">
        {Phoenix.HTML.raw(@body_html)}
      </div>
    </div>
    """
  end

  # Header per (kind, state-variant) ------------------------------------------

  defp header_for(%State.Running{kind: "planner_command_run"}), do: gettext("Tore is working on it")
  defp header_for(%State.NeedsUser{kind: "planner_command_run"}), do: gettext("Tore needs a moment")
  defp header_for(%State.Applied{kind: "planner_command_run"}), do: gettext("Tore adjusted the plan")
  defp header_for(%State.Failed{kind: "planner_command_run"}), do: gettext("Tore couldn't update the plan")
  defp header_for(%State.Reverted{kind: "planner_command_run"}), do: gettext("Reverted")
  defp header_for(_), do: gettext("Tore")

  # Body per state-variant ----------------------------------------------------

  defp body(%State.Running{phase: phase}), do: escape(phase_label(phase))
  defp body(%State.NeedsUser{question: q}), do: escape(q)
  defp body(%State.Applied{artifacts: artifacts}), do: escape(summary_text(artifacts))
  defp body(%State.Failed{failure_user_message: msg}), do: escape(msg)
  defp body(%State.Reverted{}), do: escape(gettext("Changes reverted."))

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp phase_label(:gathering_context), do: gettext("Gathering context")
  defp phase_label(:proposing), do: gettext("Proposing")
  defp phase_label(:verifying), do: gettext("Verifying")

  defp summary_text(artifacts) do
    case Enum.find(artifacts, fn a -> match?(%RunSummary{}, a) end) do
      nil -> gettext("Done.")
      %RunSummary{} = rs -> Artifact.summary(rs).text_fallback
    end
  end
end
