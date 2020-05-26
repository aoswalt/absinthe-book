# Chapter 9: Tuning Resolution

The last major tool that Absinthe provides for tweaking the execution of a document: plugins (p. 167)

The pipeline is at the heart of how Absinthe works, and manipulating the parts that make up the pipeline, phases, is key to many of the advanced features that Absinthe offers (p. 167)

Absinthe is a lot like an interpreter. When you pass it a GraphQL document, it's parsed into an abstract syntax tree (AST), converted into an intermediate structure we call a _Blueprint_ that houses additional metadata, and fed through configured validation and pre-processing logic before being ultimately executed (pp. 167-168)

A _phase_ is simply a module that has a `run/2` function, accepting an input and options, and returning an output (p. 168)

After the `%Absinthe.Blueprint{}` struct is created, the rest of the document processing pipeline centers on the manipulation of the blueprint, passed from phase to phase (p. 168)

Broadly speaking Absinthe phases fall into three categories: (p. 168)
* Preparation phases
* Execution phases
* Result building phases

A plugin then is essentially an upgraded middleware module that has some specific hooks into this Resolution phase. These hooks let us run some stuff before and after resolution, as well as the give us the ability to control whether additional phases need to happen (p. 169)

## Understanding the Problem

Anytime we need do something like load an Ecto schema `has_many` association in a resolver, then query child values, we can quickly find ourselves mired in what's referred to as the "N + 1 problem", and performing more database work than we expect (p. 169)

One of the keys under the `%Absinthe.Resolution{}` struct is `:middleware`, and it contains a list of all remaining middleware queued up to run on this field (p. 171)

Absinthe goes through each in turn and executes the `:name` and `:id` fields our query document selected (p. 173)

If we return N items from the menu_items field, the name and id field resolvers will each run N times (p. 174)

This is both the simplest and most optimal way to proceed when all those fields do is a `Map.get` on their source, but this approach won't serve if we need to execute fields in parallel, or if we want to work with a group of fields all together (p. 174)

We're fully resolving the category field on each menu item before moving on (p. 176)

## Using Built-in Plugins

A Plugin in Absinthe is any module that implements the `Absinthe.Plugin` behaviour. It is not uncommon for a plugin module to also implement the `Absinthe.Middleware` behaviour, because the two behaviours work together (p. 176)

The middleware callbacks handle changes that need to happen to each individual field, and the Plugin callbacks operate at the document level (p. 176)

### Async

A step in the direction of efficient execution would be to run each field concurrently. It doesn't get rid of the N+1 query, but it does mean that by doing all the N at the same time we can improve our response time. While obviously not the optimal solution for SQL based data, async execution is a very useful tool when dealing with external APIs (p. 176)

our `category_for_item/3` resolver function and make it async. To do this we'll make use of a helper built into Absinthe, `async/1`, which will import from the `Absinthe.Resolution.Helpers` module (p. 177)

```elixir
import Absinthe.Resolution.Helpers, only: [async: 1]

# Rest of file

def category_for_item(menu_item, _, _) do
  async(fn ->
    query = Ecto.assoc(menu_item, :category)
    {:ok, PlateSlate.Repo.one(query)}
  end)
end
```

Every resolver we've written so far has returned either an `{:ok, value}` or `{:error, error}` tuple. Here though we're seeing the third and final tuple which has the form `{:middleware, MiddlewareModule, options}` and amounts to telling Absinthe "Hey, hand off the execution of this field to this middleware with these options" (p. 177)

the entire contents of the `async/1` helper (p. 177)

```elixir
def async(fun, opts \\ []) do
  {:middleware, Middleware.Async, {fun, opts}}
end
```

Nothing in the async helper seem to be doing anything to spawn processes though, so the work has to be done inside the `Middleware.Async` (p. 178)

```elixir
defmodule Absinthe.Middleware.Async do
  @behaviour Absinthe.Middleware
  @behaviour Absinthe.Plugin

  def before_resolution(exec) do
    put_in(exec.context[__MODULE__], false)
  end

  def call(%{state: :unresolved} = res, {fun, opts}) do
    task_data = {Task.async(fun), opts}
    %{res |
      state: :suspended,
      context: Map.put(res.context, __MODULE__, true),
      middleware: [{__MODULE__, task_data} | res.middleware]
    }
  end

  def call(%{state: :suspended} = res, {task, opts}) do
    result = Task.await(task, opts[:timeout] || 30_000)
    Absinthe.Resolution.put_result(res, result)
  end

  def after_resolution(exec), do: exec

  def pipeline(pipeline, exec) do
    case exec.context do
      %{__MODULE__ => true} ->
        [Absinthe.Phase.Document.Execution.Resolution | pipeline]
      _ ->
        pipeline
    end
  end
end
```

This module is implementing both the `Absinthe.Middleware` and the `Absinthe.Plugin` behaviours. The first makes sure we can hook into individual fields when they need to use dataloader, and the other provides us before and after resolution callbacks (p. 179)

```graphql
{
  menuItems {
    category { name }
    id
  }
}
```

The first thing that happens, as the name suggests, is the `before_resolution/1` callback. The value passed to this function is an `%Absinthe.Blueprint.Execution{}` struct, from which every field's `%Absinthe.Resolution{}` struct is derived. The `before_resolution/1` callback is a good place to set up values we may need later (p. 179)

The flag will be used later to figure out whether any processes are running in the background or not (p. 179)

Absinthe will hit our `:category` field, which hands off to this middleware's call function via the `:middleware` tuple from the `async/1` function (p. 179)

Two clauses here:

The first one we'll hit immediately at the end of our resolver, because since no result has been placed on our field, the state is still `:unresolved` (p. 179)

updates the field's middleware to re-run this module when the field is unsuspended (p. 179)

When you suspend the resolution struct, Absinthe stops doing any further processing to that field and moves on to the next sibling field (p. 179)

The `name` field is unreachable until after category has finally resolved (p. 179)

Second one

When Absinthe comes back to this field, it needs a way to turn this task back into an actual value that it can continue resolution with, so we use the same trick we learned in the Debug module to re-enqueue our middleware. This time though instead of adding it at the end we add it as the very next thing, and we pass along the task we just spawned. When Absinthe comes back to the field it'll run this module again, and we'll have the opportunity to `Task.await/1` and get a value (p. 180)

After Absinthe has completed this particular walk through the document, it runs the `after_resolution` callback. This is an opportunity to do any extra transformations or loading (p. 180)

The `Absinthe.Phase.Document.Execution.Resolution` phase we've been inside this whole time only does a _SINGLE_ walk through the document (p. 180)

The callback _pipeline_ allows our plugin to have the option to tell Absinthe to run additional phases on the document based on the execution struct we returned from `after_resolution` (p. 180)

If the flag been set to true then we know there are async fields happening, and we need to go back to await them. If the it is false then, as far as this plugin is concerned there's nothing more to be done, so we leave the pipeline alone (p. 180)

![Plugin Resolution Pipeline](./path/to/img.png "Plugin Resolution Pipeline")

As Absinthe walks through the document it will come across the first suspended field, calling whatever remaining middleware exists on that field (p. 181)

### Batch

a way to aggregate values, a function that can use those aggregated values to run an SQL query, and then the ability to get those values back into individual fields (p. 181)

the `Absinthe.Middleware.Batch` plugin (p. 181)

```elixir
import Absinthe.Resolution.Helpers, only: [batch: 3]

# Rest of file

def category_for_item(menu_item, _, _) do
  batch(
    {PlateSlate.Menu, :categories_by_id},
    menu_item.category_id,
    fn categories -> {:ok, Map.get(categories, menu_item.category_id)} end
  )
end
```

The `batch/3` function takes three arguments: (p. )
* a module and function tuple indicating what function will actually run the batch
* a value to be aggregated
* and then a function for retrieving the results specific to this field

The function specified, `PlateSlate.Menu.categories_by_id/2` (p. 181)

```elixir
def categories_by_id(_, ids) do
  Category
  |> where([c], c.id in ^Enum.uniq(ids))
  |> Repo.all
  |> Map.new(fn category -> {category.id, category} end)
end
```

The resolver function is aggregating `menu_item.category_ids`, and those will get passed in as the second arg of the `categories_by_id` function (p. 182)

we do a single SQL query for two categories, id 3 and 1, and then each category field completes without any further DB querying (p. 183)

The fact that we started each category field before we completed any of them tells us that the plugin is suspending each field as it internally builds up a batch under each function, and the fact that each field ultimately completes tells us it's doing the trick of modifying the middleware to come back (p. 183)

There are small scale annoyances like the limitation of only being able to batch one thing at a time in a field, or the fact that the API can get very verbose (p. 183)

## Discovering Dataloader

The challenge here is getting the data we want efficiently, without coupling our GraphQL API tightly to the SQL structure of our data, and without stuffing our contexts full of tons of functions that exist just for GraphQL purposes. We want to respect the idea that our contexts define a boundary, and if we start just doing Ecto queries in all of our resolvers we'd be violating that boundary (p. 184)

Dataloader is a very small package that defines a minimalist API for getting data in batches (p. 184)

in our Menu item context we're going to define a Dataloader source (p. 185)

```elixir
def data() do
  Dataloader.Ecto.new(Repo, query: &query/2)
end

def query(queryable, _) do
  queryable
end
```

create ourselves a dataloader (p. 185)

```elixir
source = Menu.data()
loader = Dataloader.new |> Dataloader.add_source(Menu, source)
```

queue up some items to be loaded (p. 185)

```elixir
loader = (
  loader
  |> Dataloader.load(Menu, Menu.Item, 1)
  |> Dataloader.load(Menu, Menu.Item, 2)
  |> Dataloader.load(Menu, Menu.Item, 3)
)
```

To retrieve all queued up batches we use `Dataloader.run/1` to run a single SQl query to grab all the items we've queued up so far (p. 186)

```elixir
loader |> Dataloader.run()
```

If we use `Dataloader.get/3` again we'll see that our items are here, and we can also use `Dataloader.get_many/3` to conveniently grab several items at once (p. 186)

```elixir
iex> menu_item = loader |> Dataloader.get(Menu, Menu.Item, 2)
%PlateSlate.Menu.Item{...}

iex> menu_items = loader |> Dataloader.get_many(Menu, Menu.Item, [1,2,3])
[%PlateSlate.Menu.Item{...}, ...]
```

The idea here is that we can load up one or more batches worth of data we want to retrieve, on one or more sources, delaying the actual execution of any SQL queries until we actually need the results (p. 186)

we can also use Ecto association names (p. 186)

```elixir
iex> loader = (
...>   loader
...>   |> Dataloader.load_many(Menu, :category, menu_items)
...>   |> Dataloader.run
...> )
[debug] QUERY OK source="categories" db=5.6ms
SELECT c0."id", ...
FROM "categories" AS c0 WHERE (c0."id" = $1) [1]

iex> categories = loader |> Dataloader.get_many(Menu, :category, menu_items)
[%PlateSlate.Menu.Category{...}, ...]
```

Placing a `loader` struct inside of the Absinthe context will make it readily available in all of our resolvers (p. 186)

The schema itself supports a `context/1` callback that's perfect for setting up values that you want to be around no matter how you run GraphQL queries (pp. 186-187)

```elixir
def dataloader() do
  alias PlateSlate.Menu
  Dataloader.new
  |> Dataloader.add_source(Menu, Menu.data())
end

def context(ctx) do
  Map.put(ctx, :loader , dataloader())
end
```

The `context/1` callback gets passed the existing context value, and then we have the opportunity to make any adjustments to it that we want. This function runs after code in our `PlateSlateWeb.Context` plug (p. 187)

A `plugins/0` function on your schema module, which simply defaults to async and batch if you don't supply a custom one (p. 187)

add one to include the Dataloader plugin (p. 187)

```elixir
def plugins() do
  [Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults]
end
```

to the `:category` field and let's put dataloader to work (p. 187)

```elixir
def category_for_item(menu_item, _, %{context: %{loader: loader}}) do
  loader
  |> Dataloader.load(Menu, :category, menu_item)
  |> on_load(fn loader ->
      category = Dataloader.get(loader, Menu, :category, menu_item)
      {:ok, category}
    end)
end
```

Similar to batch, on_load hands off control to the `Absinthe.Middleware.Dataloader` module, which arranges to run our callback after the Dataloader batches have been run (p. 188)

from a category to the items on it. This direction is a bit more complicated though, because we probably ought to support ordering, filtering, and other query customization options (p. 188)

The `Dataloader.Ecto` source we're using makes this easy by accepting a tuple as the third argument, where the first element is the association or queryable, and the second arg is a map of params it passes down to our context (p. 188)

```elixir
loader
|> Dataloader.get_many(Menu, {:items, %{order: :asc}}, categories)
```

we set up our Menu data loader source with a query/2 function that we had stubbed out inside of our Menu context. This function lets you alter the Ecto query used by Dataloader to enforce access rules, or apply filters (p. 188)

refactor the `list_items/1` function so that the query building part is extracted into its own function (p. 188)

```elixir
def list_items(args) do
  args
  |> items_query
  |> Repo.all
end

defp items_query(args) do
  Enum.reduce(args, Item, fn
    {:order, order}, query ->
      query |> order_by({^order, :name})
    {:filter, filter}, query ->
      query |> filter_with(filter)
  end)
end
```

add a clause to the `query/2` function pattern matching on `Menu.Item`, and applying arguments (pp. 188-189)

```elixir
def query(Item, args) do
  items_query(args)
end

def query(queryable, _) do
  queryable
end
```

Every time dataloader queries a `Menu.Item`, the `query/2` function will pattern match on the first arg `Item` and apply the arguments specific for that queryable (p. 189)

We can easily wire efficient and flexible loading into the `:items` field of `our` :category object, with the same kind of filtering we do at the top level (p. 189)

```elixir
object :category do
  interfaces [:search_result]
  field :name, :string
  field :description, :string
  field :items, list_of(:menu_item) do
    arg :filter, :menu_item_filter
    arg :order, type: :sort_order, default_value: :asc
    resolve &Resolvers.Menu.items_for_category/3
  end
end
```

inside of our `items_for_category/3` resolver function by using Dataloader, and passing in the arguments as part of the batch key (p. 189)

```elixir
def items_for_category(category, args, %{context: %{loader: loader}}) do
  loader
  |> Dataloader.load(Menu, {:items, args}, category)
  |> on_load(fn loader ->
    items = Dataloader.get(loader, Menu, {:items, args}, category)
    {:ok, items}
  end)
end
```

the `:items_for_category` and `:category_for_item` resolver functions, we can begin to sense a pattern here. In both cases we're just grabbing the parent item, adding it dataloader, and then getting it back out in the `on_load` callback (p. 190)

This is such a common pattern that Absinthe provides a helper that lets you turn both of these resolvers into a nice one liner (p. 190)

```elixir
resolve dataloader(Menu, :items)
```

Here is the `dataloader/2` helper from within Absinthe itself (p. 191)

```elixir
def dataloader(source, key) do
  fn parent, args, %{context: %{loader: loader}} ->
    loader
    |> Dataloader.load(loader, {key, args}, parent)
    |> on_load(fn loader ->
      result = Dataloader.get(loader, {key, args}, parent)
      {:ok, result}
    end)
  end
end
```

the `dataloader` function is simply building exactly the same resolver functions we've been doing. With this in place, we don't even need the two dedicated functions within the `Resolvers.Menu` module at all, and can remove them (p. 191)

## Moving On

* retrieving the current menu item for a given order's order item. This one is tricky, since it crosses contexts and order_item is an embedded schema
* a helper that only requires that you pass in the dataloader source, which looks like `dataloader(Menu)`. See if you can figure out how it knows what field it's on
