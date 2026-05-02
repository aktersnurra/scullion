defmodule Scullion.Adapters.OpenRouter do
  @behaviour Scullion.LLM

  @api_url "https://openrouter.ai/api/v1/chat/completions"

  @impl Scullion.LLM
  def generate_plan(constraints) do
    {system, user} = Scullion.LLM.Prompts.plan_weekly(constraints)
    chat(system, user)
  end

  @impl Scullion.LLM
  def generate_prep_guide(plan) do
    {system, user} = Scullion.LLM.Prompts.prep_guide(plan)
    chat(system, user)
  end

  @impl Scullion.LLM
  def suggest_recipes(_context), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def extract_recipe_from_html(_html), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def parse_receipt_image(_image), do: {:error, :not_implemented}

  @impl Scullion.LLM
  def parse_deals_image(_image), do: {:error, :not_implemented}

  defp chat(system_prompt, user_prompt) do
    body = %{
      model: model(),
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_prompt}
      ]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"Authorization", "Bearer #{api_key()}"},
             {"HTTP-Referer", "https://scullion.gustafrydholm.xyz"},
             {"X-Title", "Scullion"}
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        usage = extract_usage(body)

        with {:ok, parsed} <- Jason.decode(content) do
          {:ok, parsed, usage}
        end

      {:ok, %{status: 402}} ->
        {:error, :provider_budget_exceeded}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:openrouter_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp extract_usage(%{"usage" => usage}) when is_map(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      cost_usd: usage["cost"] || 0.0
    }
  end

  defp extract_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0, cost_usd: 0.0}

  defp api_key, do: Application.fetch_env!(:scullion, :openrouter_api_key)
  defp model, do: Application.get_env(:scullion, :openrouter_model, "anthropic/claude-3-5-haiku")
end
