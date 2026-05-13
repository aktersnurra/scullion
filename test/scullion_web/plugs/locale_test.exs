defmodule ScullionWeb.Plugs.LocaleTest do
  use ScullionWeb.ConnCase, async: true

  alias ScullionWeb.Plugs.Locale

  test "sets locale from current_user" do
    user = %{locale: "sv"}
    _conn =
      build_conn()
      |> assign(:current_user, user)
      |> Locale.call([])

    assert Gettext.get_locale(ScullionWeb.Gettext) == "sv"
  end

  test "defaults to sv when no current_user" do
    _conn =
      build_conn()
      |> assign(:current_user, nil)
      |> Locale.call([])

    assert Gettext.get_locale(ScullionWeb.Gettext) == "sv"
  end
end
