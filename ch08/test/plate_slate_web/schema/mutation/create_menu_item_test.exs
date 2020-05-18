defmodule PlateSlateWeb.Schema.Mutation.CreateMenuItemTest do
  use PlateSlateWeb.ConnCase, async: true

  import Ecto.Query

  alias PlateSlate.Menu
  alias PlateSlate.Repo

  setup do
    PlateSlate.Seeds.run()

    category_id =
      Menu.Category
      |> where(name: "Sandwiches")
      |> Repo.one!()
      |> Map.fetch!(:id)
      |> to_string()

    {:ok, category_id: category_id}
  end

  @query """
  mutation ($menuItem: MenuItemInput!) {
    createMenuItem(input: $menuItem) {
      errors { key message }
      menuItem {
        name
        description
        price
      }
    }
  }
  """
  test "createMenuItem field creates an item", %{conn: conn, category_id: category_id} do
    menu_item = %{
      "name" => "French Dip",
      "description" => "Roast beef, carmelized onions, horseradish, ...",
      "price" => "5.75",
      "categoryId" => category_id
    }

    conn = post(conn, "/api", query: @query, variables: %{"menuItem" => menu_item})

    assert json_response(conn, 200) == %{
             "data" => %{
               "createMenuItem" => %{
                 "errors" => nil,
                 "menuItem" => %{
                   "name" => menu_item["name"],
                   "description" => menu_item["description"],
                   "price" => menu_item["price"]
                 }
               }
             }
           }
  end

  test "creating a menu item with an existing name fails", %{conn: conn, category_id: category_id} do
    menu_item = %{
      "name" => "Reuben",
      "description" => "Roast beef, carmelized onions, horseradish, ...",
      "price" => "5.75",
      "categoryId" => category_id
    }

    conn = post(conn, "/api", query: @query, variables: %{"menuItem" => menu_item})

    assert json_response(conn, 200) == %{
             "data" => %{
               "createMenuItem" => %{
                 "errors" => [
                   %{"key" => "name", "message" => "has already been taken"}
                 ],
                 "menuItem" => nil
               }
             }
           }
  end
end
