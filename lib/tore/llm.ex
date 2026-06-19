defmodule Tore.LLM do
  @moduledoc """
  Transport-only behaviour for talking to an LLM provider.

  The adapter is responsible for HTTP, model selection, and decoding the
  provider response into a raw map or string. It is NOT responsible for
  shaping that map into domain types — that lives in the calling context
  (e.g. `Tore.Pantry`, `Tore.Costs`, `Tore.Harness.ReceiptIngestion`).
  """

  @type blob :: {:image, binary()} | {:pdf, binary()}
  @type usage :: %{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          cost_usd: number()
        }

  @typedoc """
  Options for `text/3` and `vision/4`:

    * `:model` — override the default model id for this call.
    * `:response_format` — provider response_format; defaults to
      `%{type: "json_object"}`. Pass a JSON-schema map for strict output.
  """
  @type opts :: keyword()

  @callback text(system :: String.t(), user :: String.t(), opts()) ::
              {:ok, map() | String.t(), usage()} | {:error, term()}

  @callback vision(blobs :: [blob()], system :: String.t(), user :: String.t(), opts()) ::
              {:ok, map(), usage()} | {:error, term()}

  @callback chat(system :: String.t(), messages :: [map()]) ::
              {:ok, String.t(), usage()} | {:error, term()}

  @type tool_call :: %{id: String.t(), name: String.t(), args: %{String.t() => term()}}
  @type tool_response ::
          {:message, String.t()}
          | {:tool_calls, [tool_call()]}

  @callback chat_with_tools(
              system :: String.t(),
              messages :: [map()],
              tools :: [map()],
              opts :: keyword()
            ) :: {:ok, tool_response(), usage()} | {:error, term()}
end
