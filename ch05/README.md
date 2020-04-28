# Chapter 5: Making a Change with Mutations

GraphQL also supports mutations, which allow users of the API to modify server-side data (p. 77)

GraphQL mutations as roughly analogous to POST, PUT, and DELETE operations (p. 77)

responses from GraphQL mutations can be tailored, just as with GraphQL query operations (p. 77)

## Defining a Root Mutation Type

need to define a root mutation type, just as we did for queries. This will be used as the entrypoint for GraphQL mutation operations, and will define—based on the mutation fields that we add—the complete list of capabilities that users of our API will have available to modify data (p. 77)

define the root mutation type by using the mutation macro in our schema (p. 77)
```elixir
mutation do
  # Mutation fields will go here
end
```

Both macros, query and mutation, are used to define the root object types for their respective GraphQL operations (p. 78)

we add mutation fields directly inside the mutation block (which defines the root mutation object type (p. 78)

```elixir
mutation do
  field :create_menu_item, :menu_item do
  end
end
```

Most mutations that create something return it as the result of the field (p. 78)

### Modeling with an Input Object

Use an input object to model the data that you’re expecting (pp. 78-79)

```elixir
input_object :menu_item_input do
  field :name, non_null(:string)
  field :description, :string
  field :price, non_null(:decimal)
  field :category_id, non_null(:id)
end
```

you can’t use object types for user input; instead, you need to create object types for use in arguments (p. 79)

it forces you to focus on the discrete package of data that you need for specific mutations (p. 79)

technical differences between objects and input objects. Input object fields can only be valid input types, which excludes unions, interfaces, and objects. You also can’t form cycles with input objects, whereas cycles are permitted with objects (p. 79)

a float is a very poor choice for monetary math operations (p. 79)

define the `:decimal` type using the scalar macro (p. 79)

```elixir
scalar :decimal do
  parse fn
    %{value: value}, _ ->
      Decimal.parse(value)
  _, _ ->
    :error
end

  serialize &to_string/1
end
```

change the `:price` field to a `:decimal` (p. 80)
```elixir
field :price, :decimal
```

define an `:input` argument on our `:create_menu_item` field, using our `:menu_item_input` type (p. 80)

```elixir
mutation do
  field :create_menu_item, :menu_item do
    arg :input, non_null(:menu_item_input)
    resolve &Resolvers.Menu.create_item/3
  end
end
```

the name input here because it’s a convention of the Relay client-side framework for mutations (p. 80)

The actual behavior that will occur when users use createMenuItem in GraphQL documents is the responsibility of the resolver function for our mutation field (p. 80)

## Building the Resolver

ulitmately passing the `:input` argument to a changeset function (pp. 80-81)
```elixir
def create_item(_, %{input: params}, _) do
  case Menu.create_item(params) do
    {:error, _} ->
      {:error, "Could not create menu item"}
    {:ok, _} = success ->
      success
  end
end

def create_item(attrs \\ %{}) do
  %Item{}
  |> Item.changeset(attrs)
  |> Repo.insert()
end
```

While the return value of a successful `Repo.insert/2` is compatible with a resolution result, the `{:error, changeset}` that it can return isn’t (p. 81)

we declared what type of object it would have as a result. We did this by passing `:menu_item` as the second argument to the field macro (p. 81)

our API clients can query the result object type just like they would in a query operation. They can then extract exactly the information they want from the created object to update the user interface of their application (p. 82)

we can dig into the returned `:menu_item` object type and pull out any information that we need (p. 82)
```graphql
mutation CreateMenuItem($menuItem: MenuItemInput!) {
  createMenuItem(input: $menuItem) {
    id
    name
    description
    price
    category { name }
    tags { name }
  }
}
```

### Testing Our Request

The value that’s returned for the menu item is housed inside an object returned under the "createMenuItem" key. It would be a lot nicer to have it called "menuItem". Luckily, we can use a mechanism that GraphQL calls a field alias to help (p. 84)

### Using Field Alias for Nicer (and Unique Names)

aliasing the `createMenuItem` field to `menuItem` (p. 84)
```graphql
mutation ($menuItem: MenuItemInput!) {
  menuItem: createMenuItem(input: $menuItem) {
    name
  }
}
```

results in
```json
{
  "menuItem": {
    "name": "French Dip"
  }
}
```

This also serves for to creating multiple new menu items at once (p. 85)

GraphQL doesn’t allow duplicate field names in a request, and it wouldn’t make much sense in the resulting JSON, either (p. 85)

mark each mutation with a separate alias (p. 85)
```graphql
mutation CreateTwo($menuItem1: MenuItemInput!, $menuItem2: MenuItemInput!) {
  one: createMenuItem(input: $menuItem) { id name }
  two: createMenuItem(input: $menuItem) { id name }
}
```

Structurally, GraphQL queries and mutations are exactly the same, and there are plenty of cases where a user might want to query the same field with different sets of arguments for multiple, separate results (p. 85)

```graphql
query Meal {
  inHand: search(matching: "reu") { name }
  inGlass: search(matching: "reu") { name }
}
```

results come back with data associated to each alias (pp. 85-86)
```json
{
  "data": {
    "inHand": [
      {
        "name": "Reuben"
      }
    ],
    "inGlass": [
      {
        "name": "Lemonade"
      }
    ]
  }
}
```

## Handling Mutation Errors

users create menu items, they will be prevented from using duplicate names (p. 88)

two approaches that you can use in your Absinthe schema to give users more information when they encounter an error: using simple `:error` tuples and modeling the errors directly as types (p. 88)

### Using Tuples

Field resolvers functions return tuple values to indicate their result

```elixir
def create_item(_, %{input: params}, _) do
  case Menu.create_item(params) do
    {:error, _} ->
      {:error , "Could not create menu item"}
    {:ok, _} = success ->
      success
  end
end
```

Changesets cannot be directly consumed by Absinthe, so the errors can be extracted into a simple message (p. 89)
```elixir
case Menu.create_item(params) do
  {:error, changeset} ->
    {:error, message: "Could not create menu item", details: error_details(changeset)}
  success ->
    success
end
```

```elixir
def error_details(changeset) do
  changeset
  |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
end
```

If you go beyond returning `{:error, String.t}`, and return a map or keyword list, you must include a :message. Anything else is optional, but any error information must be serializable to JSON (p. 89)

Instead of returning a simple `{:error, String.t}` value from the resolver, we’re now returning an `{:error, Keyword.t}`, with the error information from the changeset under the `:details` key (p. 90)

errors are reported separate of data values in a GraphQL response (p. 90)

the path to the related field is included, as well as line number information (p. 90)

~~Due to a limitation of the lexer that Absinthe uses (Leex, part of Erlang/OTP), column tracking isn’t available... yet. For the moment, to be compatible with client tools, Absinthe always reports the column value as 0~~ (p. 90) (Absinthe uses `nimble_parsec` in 1.5)

### Errors as Data

rather than returning errors in GraphQL’s free-form, errors portion of the result, it might make sense to model our errors as normal data—fully defining the structure of our errors as normal types to support introspection and better integration with clients (p. 91)

existing mutation field
```elixir
mutation do
  field :create_menu_item, :menu_item do
    # Contents
  end
end
```

["Existing Mutation Relationship" - Direct from mutation to result](../images/ch04_simple-errors.png "Existing Mutation Relationship")

instead of returning the menu item directly, our mutation field returned an object type, `:menu_item_result`, that would sit in the middle (p. 92)

```elixir
object :menu_item_result do
  field :menu_item, :menu_item
  field :errors, list_of(:input_error)
end
```

This result models each part of the output, the menu item and the errors. The :errors themselves are an object, which we’ll put in the schema because they’re generic enough to be used in a variety of places (p. 92)

```elixir
@desc "An error encountered trying to persist input"
object :input_error do
  field :key, non_null(:string)
  field :message, non_null(:string)
end
```

how the resulting GraphQL type structure would look like, once we modified the mutation field to declare its result to be a `:menu_item_result`

["Returning A Mutationation Result" - Errors are returned per mutation](../images/ch04_nested-error-data.png "Returning A Mutationation Result")

```elixir
case Menu.create_item(params) do
  {:error, changeset} ->
    {:ok, %{errors: transform_errors(changeset)}}
  {:ok, menu_item} ->
    {:ok, %{menu_item: menu_item}}
end
```

regardless of error state, an `:ok` tuple is returned; it’s just doing the work of translating database errors into values that can be transmitted back to clients (p. 94)

GraphQL documents from the clients wouldn’t look much different; they’d just be a level deeper (p. 94)

```graphql
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
```

can interpret the success of the result by checking the value of `menuItem` and/or `errors`, then give feedback to users appropriately (p. 94)

Because the errors are returned as result of specific fields, this means that, even in cases where the client sends multiple mutations in a single document, any errors encountered can be tied to the specific mutation that failed (p. 94)

If users don’t need to know the structure of your errors ahead of time, or if you don’t think supporting introspection for documentation purposes is worth it, even this basic modeling is overkill; just return simple `:error` tuples instead. They’re low ceremony and flexible enough to support most use cases (p. 95)
