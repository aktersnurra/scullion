defmodule Tore.Adapter do
  @moduledoc """
  Transport behaviour for an LLM provider.

  One method. Send the body, get the raw response back. No knowledge of chat
  shapes, vision blobs, JSON schemas, or domain decoding — `Tore.LLM` owns
  all of that.

  The body shape is OpenAI's `/chat/completions` schema (the de-facto
  lingua franca). Provider-specific adapters translate to/from their own
  wire format as needed.
  """

  @callback request(body :: map()) :: {:ok, map()} | {:error, term()}
end
