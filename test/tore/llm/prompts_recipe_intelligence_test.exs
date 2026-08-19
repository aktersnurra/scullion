defmodule Tore.LLM.PromptsRecipeIntelligenceTest do
  use ExUnit.Case, async: true

  alias Tore.LLM.Prompts

  describe "find_recipe_web/2" do
    test "returns a {system, user} pair carrying the query" do
      {system, user} = Prompts.find_recipe_web("weeknight ramen", nil)

      assert is_binary(system)
      assert user =~ "weeknight ramen"
    end

    test "instructs the model to return urls, not recipe bodies" do
      {system, _user} = Prompts.find_recipe_web("ramen", nil)

      assert system =~ "url"
      refute system =~ "invent"
    end

    test "the prompt is English even for a Swedish household" do
      {system, _user} = Prompts.find_recipe_web("ramen", "sv")

      assert system =~ "recipe"
      assert system =~ "Swedish"
    end

    test "web_candidates_json_schema/0 names the candidates array" do
      schema = Prompts.web_candidates_json_schema()

      assert schema.json_schema.name == "web_candidates"
      assert get_in(schema.json_schema.schema, [:properties, :candidates])
    end
  end

  describe "generate_recipe_variant/3" do
    @source %{
      title: "Miso Ramen",
      base_servings: 4,
      instructions: "Simmer the broth. Cook the noodles.",
      ingredients: [%{name: "miso paste", quantity: "2", unit: "msk"}]
    }

    test "returns a {system, user} pair carrying source recipe and instruction" do
      {system, user} = Prompts.generate_recipe_variant(@source, "make it vegetarian", nil)

      assert is_binary(system)
      assert user =~ "Miso Ramen"
      assert user =~ "make it vegetarian"
    end

    test "the system prompt carries the shared recipe schema rules" do
      {system, _user} = Prompts.generate_recipe_variant(@source, "simpler", nil)

      assert system =~ "MISE EN PLACE"
      assert system =~ "title is required"
    end

    test "locale is a parameter, not baked into the prompt" do
      {system_none, _} = Prompts.generate_recipe_variant(@source, "simpler", nil)
      {system_sv, _} = Prompts.generate_recipe_variant(@source, "simpler", "sv")

      refute system_none =~ "Swedish"
      assert system_sv =~ "Swedish"
    end
  end
end
