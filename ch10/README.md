# Chapter 10: Driving Phoenix Actions with GraphQL

GraphQL APIs are commonly used (and in fact, GraphQL was originally developed) to support data-fetching for user interfaces that aren't co-located with the server code (p. 195)

You can use the power of GraphQL directly from other parts of your Elixir application too (p. 195)

You can even use it to build more traditional server-side rendered user interfaces (p. 195)

## Building an Action

the controller, where you should replace its existing contents entirely (p. 196)

```elixir
defmodule PlateSlateWeb.ItemController do
  use PlateSlateWeb, :controller
  use Absinthe.Phoenix.Controller, schema: PlateSlateWeb.Schema
end
```

The way that `Absinthe.Phoenix.Controller` works is that it gives you a way to associate a GraphQL query with a controller action, and use the data looked up from that query in your controller. We won't be replacing the controller actions but rather augmenting them by utilizing all the lookup ability we've already written, letting it focus on just managing the HTTP connection (p. 197)

`@graphql` module attribute on which we are putting a string with a GraphQL query (p. 197)

```elixir
@graphql """
{
  menu_items {
    name
  }
}
"""
def index(conn, result) do
  render(conn, "index.html", items: result.data["menu_items"] || [])
end
```

ordinary looking Phoenix controller callback `index/2` which gets the HTTP conn, some params, and then renders an `index.html` (p. 197)

At a high level the controller action is acting as a GraphQL client. Instead of looking up menu items by directly hitting the database or `PlateSlate.Menu` context it submits a GraphQL query to Absinthe, and then it receives the results of that query as the second argument to the `index/2` function (p. 197)

The result that we get in the second argument to our `index/2` function is essentially the output you'd get from using `Absinthe.run` manually (p. 199)

A directive is a type that's defined in our schema, just like an object or a scalar, and we can use these types to annotate parts of our GraphQL documents for special handling (p. 199)

`Absinthe.Phoenix` ships with a couple of directives, which we can get access to by importing them into our own schema (p. 199)

```elixir
import_types Absinthe.Phoenix.Types
```

Directives are placed in GraphQL documents prefixed with a `@` sigil (p. 200)

```elixir
@graphql """
query Index @action(mode: INTERNAL) {
```

the `:action` directive placed in the GraphQL document via @action, marking the query operation (p. 200)

directives can take arguments (p. 200)

The `mode: INTERNAL` bit isn't a strange new syntax; this is a totally ordinary argument with an enum value that tells `Absinthe.Phoenix` that we want to have it adjust the results of executing the query to suit internal Elixir usage (p. 200)

Because we placed the `@action` directive on our query, flagging the query as something we want to run in the `INTERNAL` mode, we get atom keys (p. 200)

When `Absinthe.Phoenix` ran the query, it used special phases that looked for these flags to adjust the output for us (p. 200)

get the full structs of each menu item (p. 200)

```elixir
@graphql """
query Index @action(mode: INTERNAL) {
  menu_items
}
"""
```

our GraphQL query now just has a bare menu_items field, instead of the previous `menu_items { name }`. When using `@action` this bears special significance: it will return the bare data from field resolvers (pp. 200-201)

What we want to have happen here is for the contents of the category resolver to simply get placed into the results we were getting before. To accomplish this, we'll use another directive, `:put` (p. 202)

```elixir
@graphql """
query Index @action(mode: INTERNAL) {
  menu_items @put {
    category
  }
}
"""
```

The use of `@put` in our document indicates to `Absinthe.Phoenix` that instead of narrowing down the results of the `menu_items` field to only the fields in the selection set, we want to put those values into the previous result (p. 202)

Directives can't force the server to do anything, they just ask nicely. The `:action` and `:put` directives we're using here are ignored completely unless run through `Absinthe.Phoenix.Controller`. This means that if someone uses them in a normal API, they are ignored completely, and any sensitive values remain safely on the server (p. 203)

## Handling Input

using the `get_session/2` function provided by the `Plug.Conn` module to check the user provided cookie for an `:employee_id`. If there is such an id and it matches up to a user, we put that user in the connection `:assigns` so it's available broadly within our UI, and we put it in the `Absinthe.Plug` context so that our GraphQL queries have access to it too. If the user isn't authenticated they'll just be re-directed to the login page, and whatever session info they have is cleared out just in case it's erroneous (p. 204)

applied to the item routes, but not the session routes (p. 205)

We can hook these parameters up to a GraphQL document by naming variables within a document after their corresponding parameter (p. 207)

```elixir
@graphql """
mutation ($email: String!, $password: String!) @action(mode: INTERNAL) {
  login(role: EMPLOYEE, email: $email, password: $password)
}
"""
def create(conn, %{data: %{login: result}}) do
```

The login field requires two arguments, email and password, which we're passing in via variables. Those variable names match up the parameter names set in our form, so when we submit the form, `Absinthe.Phoenix.Controller` grabs those parameters and uses them as GraphQL variable inputs (p. 208)

## Complex Queries

provide an order history that we'll display on each menu item `show` page. We'll have to start by adding some fields to our GraphQL schema in order to connect menu items over to the orders, and we'll need to do a few tweaks at the database and context level (p. 210)

### Connecting Items to Orders

show the total quantity of the menu item sold, as well as the total revenue we've earned from it over time (p. 211)

```elixir
object :menu_item do
  # Rest of menu item object
  field :order_history, :order_history do
    arg :since, :date
    middleware Middleware.Authorize, "employee"
    resolve &Resolvers.Ordering.order_history/3
  end
end

object :order_history do
  field :orders, list_of(:order) do
    resolve: &Resolvers.Ordering.orders/3
  end

  field :quantity, non_null(:integer) do
    resolve: Resolvers.Ordering.stat(:quantity)
  end

  @desc "Gross Revenue"
  field :gross, non_null(:float) do
    resolve: Resolvers.Ordering.stat(:gross)
  end
end
```

Instead of doing something like `field :order_history, list_of(:order)` we have this interstitial `:order_history` object, and what it does is provide us a place to expose meta-data alongside the actual orders themselves (p. 211)

something new with the `:gross` and `:quantity` fields. On the `:orders` field the `resolver:` option is an anonymous function, but on these two statistics fields we're actually calling a function to build a resolver function dynamically (p. 212)

a top level way to get a menu item by id (p. 212)

```elixir
query do
  # Other query fields
  field :menu_item, :menu_item do
    arg :id, non_null(:id)
    resolve &Resolvers.Menu.get_item/3
  end
end
```

the corresponding resolver (p. 212)

```elixir
def get_item(_, %{id: id}, %{context: %{loader: loader}}) do
  loader
  |> Dataloader.load(Menu, Menu.Item, id)
  |> on_load(fn loader -> {:ok, Dataloader.get(loader, Menu, Menu.Item, id)} end)
end
```

Dataloader isn't mandatory here since it isn't super common to have a large number of top level queries by ID, it makes the resolver function a bit more versatile, and we could use the same function on any other field that needs to look up an item by ID in the future (p. 212)

enable queries like (p. 212)

```elixir
{
  menu_item(id: "1") {
    name
    order_history(since: "2017-01-01") {
      quantity
      gross
      orders { orderedAt customerNumber }
    }
  }
}
```

while it makes sense to place the since: argument on the `order_history` field itself, we really need that value in all three resolvers underneath it (p. 213)

```elixir
def order_history(item, args, _) do
  one_month_ago = Date.utc_today() |> Date.add(-30)
  args = Map.update(args, :since, one_month_ago, fn date ->
    date || one_month_ago
  end)
  {:ok, %{item: item, args: args}}
end
```

The resolver for the `order_history` field itself simply grabs the arguments and the `menu_item` and it passes those through as a map. This is how we can get access to those values within the `:quantity` and `:orders` fields, because the `order_history` return value is used as the parent value for each of their resolvers (p. 213)

```elixir
def orders(%{item: item, args: args}, _, _) do
  batch({Ordering, :orders_by_item_name , args}, item.name, fn orders ->
    {:ok, Map.get(orders, item.name, [])}
  end)
end
```

Although there aren't N+1 concerns when loading a single menu item, we'll be re-using these fields in the index at the end, and it's generally a wise approach to avoid N+1 style coding proactively. The batch plugin makes it particularly easy to handle the statistics, so we'll just use that for loading all the data here instead of setting up a Dataloader source for the Ordering context (p. 213)

the `orders/3` resolver sets up a batch key of `{Ordering, :orders_by_item_name, args}` and it aggregates the `item.name` value, which means that it will call the `Ordering.orders_by_item_name/2` function as `Ordering.orders_by_item_name(args, aggregated_names)`. The output of that function will be a map containing orders for each menu item by name, so we can just pull out the orders for this specific item (p. 213)

The batch function itself is where we use the `order_items` view we created earlier to do some pretty ordinary filtering (pp. 213-214)

```elixir
def orders_by_item_name(%{since: since}, names) do
  query = from [i, o] in name_query(since, names),
    order_by: [desc: o.ordered_at],
    select: %{name: i.name, order: o}

  query
  |> Repo.all()
  |> Enum.group_by(& &1.name, & &1.order)
end

defp name_query(since, names) do
  from i in "order_items",
    join: o in Order,
    on: o.id == i.order_id,
    where: o.ordered_at >= type(^since, :date),
    where: i.name in ^names
end
```

The meat of the query happens in the `name_query` helper function, which we'll also use for the stats retrieval (p. 214)

these functions receive the `:since` argument and aggregated names, and create a mapping of menu item names to orders on that item (p. 214)

Aggregating the statistics on the orders (p. 214)

```elixir
def orders_stats_by_name(%{ since: since}, names) do
  from(i in name_query(since, names),
    group_by: i.name,
    select: {i.name, %{
      quantity: sum(i.quantity),
      gross: type(sum(fragment("? * ?", i.price, i.quantity)), :decimal)
    }})
  |> Repo.all()
  |> Map.new()
end
```

computing both statistics at the same time (p. 214)

```elixir
%{
  "Chocolate Milkshake" => %{quantitiy: 4, gross: 12.0},
  "French Fries" => %{quantitiy: 2, gross: 1.0},
}
```

By returning both statistics we can reduce the boilerplate in our resolver related to loading these statistics (p. 214)

```elixir
def stat(stat) do
  fn %{item: item, args: args}, _, _ ->
    batch(
      {Ordering, :orders_stats_by_name , args},
      item.name,
      fn results -> {:ok , results[item.name][stat] || 0} end
    )
  end
end
```

can think of the `stat/1` function as a resolver function builder. We pass in the stat that we want from the schema like `Resolvers.Ordering.stat(:quantity)` or `Resolvers.Ordering.stat(:gross),` and then it returns a resolver function that sets up the generic stats batch, and then pulls out the specific stat we care about via `results[item.name][stat]` (p. 215)

### Displaying Order History

the details of a specific menu item, along with the its order history and the statistics (p. 215)

```graphql
query ($id: ID!, $since: Date) {
  menu_item(id: $id) @put {
    order_history(since: $since) {
      quantity
      gross
      orders
    }
  }
}
```

setting a configuration value on the use `Absinthe.Phoenix.Controller` invocation. When all of the GraphQL documents within a controller should all use the `mode: :internal` option, you can simply specify this on the use call, so that you don't have to add that boilerplate to every document (p. 216)

The `variables/1` function comes from `Absinthe.Phoenix`, and is a way for us to access the bare inputs to the GraphQL query (p. 216)

add the same feature to the index page with almost no additional effort (p. 218)

```graphql
query {
  menu_items @put {
    category
    order_history {
      quantity
    }
  }
}
```

added a nice feature to both the menu item show and index page by making what's effectively one change to our schema (p. 219)
