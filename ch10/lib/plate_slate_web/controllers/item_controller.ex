defmodule PlateSlateWeb.ItemController do
  use PlateSlateWeb, :controller
  use Absinthe.Phoenix.Controller,
    schema: PlateSlateWeb.Schema,
    action: [mode: :internal]

  @graphql """
  query {
    menu_items @put {
      category
      order_history {
        quantity
      }
    }
  }
  """
  def index(conn, result) do
    render(conn, "index.html", items: result.data.menu_items)
  end

  @graphql """
  query ($id: ID!, $since: Date) {
    menu_item(id: $id) @put {
      order_history(since: $since) {
        quantity
        gross
        orders
      }
    }
  }
  """
  def show(conn, %{data: %{menu_item: nil}}) do
    conn
    |> put_flash(:info, "Menu item not found")
    |> redirect(to: "/admin/items")
  end

  def show(conn, %{data: %{menu_item: item}}) do
    since = variables(conn)["since"] || "2018-01-01"
    render(conn, "show.html", item: item, since: since)
  end
end
