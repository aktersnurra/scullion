defmodule Tore.LLM.Spec do
  @moduledoc """
  Wire-spec behaviour for an LLM. Implementations encode a specific provider
  body shape (OpenAI, Anthropic, …) and delegate transport to a `Tore.Adapter`.

  Contexts never call a Spec module directly — they go through the
  `Tore.LLM` facade, which dispatches to the configured Spec.
  """

  @type blob :: {:image, binary()} | {:pdf, binary()}
  @type usage :: %{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          cost_usd: number()
        }
  @type opts :: keyword()

  @type tool_call :: %{id: String.t(), name: String.t(), args: %{String.t() => term()}}
  @type tool_response :: {:message, String.t()} | {:tool_calls, [tool_call()]}

  @callback text(system :: String.t(), user :: String.t(), opts()) ::
              {:ok, map(), usage()} | {:error, term()}

  @callback vision(blobs :: [blob()], system :: String.t(), user :: String.t(), opts()) ::
              {:ok, map(), usage()} | {:error, term()}

  @callback chat(system :: String.t(), messages :: [map()], opts()) ::
              {:ok, String.t() | nil, usage()} | {:error, term()}

  @callback chat_with_tools(
              system :: String.t(),
              messages :: [map()],
              tools :: [map()],
              opts()
            ) :: {:ok, tool_response(), usage()} | {:error, term()}
end
