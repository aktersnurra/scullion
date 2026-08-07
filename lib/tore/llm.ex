defmodule Tore.LLM do
  @moduledoc """
  Facade contexts call. Dispatches to the configured `Tore.LLM.Spec`
  implementation — by default `Tore.LLM.OpenAI`. Callers never see the
  wire shape or the underlying provider.

  `:llm_spec` remains injectable so contexts use a uniform facade while
  `Tore.LLM.OpenAI` owns OpenAI body construction and response decoding.
  """

  @type blob :: {:image, binary()} | {:pdf, binary()}
  @type usage :: Tore.LLM.Spec.usage()
  @type tool_response :: Tore.LLM.Spec.tool_response()

  def text(system, user, opts \\ []), do: spec().text(system, user, opts)

  def vision(blobs, system, user, opts \\ []), do: spec().vision(blobs, system, user, opts)

  def chat(system, messages, opts \\ []), do: spec().chat(system, messages, opts)

  def chat_with_tools(system, messages, tools, opts),
    do: spec().chat_with_tools(system, messages, tools, opts)

  defp spec, do: Application.get_env(:tore, :llm_spec, Tore.LLM.OpenAI)
end
