defmodule PlateSlateWeb.ItemController do
  use PlateSlateWeb, :controller
  use Absinthe.Phoenix.Controller,
    schema: PlateSlateWeb.Schema,
    action: [mode: :internal]

  @graphql """
  query {
    menu_items @put {
      category
    }
  }
  """
  def index(conn, result) do
    render(conn, "index.html", items: result.data.menu_items)
  end
end
