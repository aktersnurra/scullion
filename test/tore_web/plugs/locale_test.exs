defmodule ToreWeb.Plugs.LocaleTest do
  use ToreWeb.ConnCase, async: true

  alias ToreWeb.Plugs.Locale

  test "sets locale from current_user" do
    user = %{locale: "sv"}

    _conn =
      build_conn()
      |> assign(:current_user, user)
      |> Locale.call([])

    assert Gettext.get_locale(ToreWeb.Gettext) == "sv"
  end

  test "defaults to sv when no current_user" do
    _conn =
      build_conn()
      |> assign(:current_user, nil)
      |> Locale.call([])

    assert Gettext.get_locale(ToreWeb.Gettext) == "sv"
  end
end
