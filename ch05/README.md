# Chapter 5: Making a Change with Mutations

GraphQL also supports mutations, which allow users of the API to modify server-side data

GraphQL mutations as roughly analogous to POST, PUT, and DELETE operations

responses from GraphQL mutations can be tailored, just as with GraphQL query operations

## Defining a Root Mutation Type

need to define a root mutation type, just as we did for queries. This will be used as the entrypoint for GraphQL mutation operations, and will define—based on the mutation fields that we add—the complete list of capabilities that users of our API will have available to modify data

define the root mutation type by using the mutation macro in our schema

```elixir
mutation do
  # Mutation fields will go here
end
```


Both macros, query and mutation, are used to define the root object types for their respective GraphQL operations

we add mutation fields directly inside the mutation block (which defines the root mutation object type

```elixir
mutation do
  field :create_menu_item, :menu_item do
  end
end
```

Most mutations that create something return it as the result of the field

You’ll use an input object to model the data that you’re expecting

```elixir
input_object :menu_item_input do
  field :name, non_null(:string)
  field :description, :string
  field :price, non_null(:decimal)
  field :category_id, non_null(:id)
end
```

you can’t use object types for user input; instead, you need to create object types for use in arguments

it forces you to focus on the discrete package of data that you need for specific mutations

technical differences between objects and input objects. Input object fields can only be valid input types, which excludes unions, interfaces, and objects. You also can’t form cycles with input objects, whereas cycles are permitted with objects

a float is a very poor choice for monetary math operations

define the `:decimal` type using the scalar macro

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

```elixir
field :price, :decimal
```

define an `:input` argument on our `:create_menu_item` field, using our `:menu_item_input` type

```elixir
mutation do
  field :create_menu_item, :menu_item do
    arg :input, non_null(:menu_item_input)
    resolve &Resolvers.Menu.create_item/3
  end
end
```

the name input here because it’s a convention of the Relay client-side framework for mutations

The actual behavior that will occur when users use createMenuItem in GraphQL documents is the responsibility of the resolver function for our mutation field

## Building the Resolver

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

While the return value of a successful `Repo.insert/2` is compatible with a resolution result, the `{:error, changeset}` that it can return isn’t

we declared what type of object it would have as a result. We did this by passing `:menu_item` as the second argument to the field macro

our API clients can query the result object type just like they would in a query operation. They can then extract exactly the information they want from the created object to update the user interface of their application

we can dig into the returned `:menu_item` object type and pull out any information that we need

The value that’s returned for the menu item is housed inside an object returned under the "createMenuItem" key

It would be a lot nicer to have it called "menuItem". Luckily, we can use a mechanism that GraphQL calls a field alias to help

want to create multiple new menu items at once

GraphQL doesn’t allow duplicate field names in a request, and it wouldn’t make much sense in the resulting JSON, either

Structurally, GraphQL queries and mutations are exactly the same, and there are plenty of cases where a user might want to query the same field with different sets of arguments for multiple, separate results

## Handling Mutation Errors

users create menu items, they will be prevented from using duplicate names

two approaches that you can use in your Absinthe schema to give users more information when they encounter an error: using simple `:error` tuples and modeling the errors directly as types

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

If you go beyond returning `{:error, String.t}`, and return a map or keyword list, you must include a :message. Anything else is optional, but any error information must be serializable to JSON

Instead of returning a simple `{:error, String.t}` value from the resolver, we’re now returning an `{:error, Keyword.t}`, with the error information from the changeset under the `:details` key

errors are reported separate of data values in a GraphQL response

the path to the related field is included, as well as line number information

Due to a limitation of the lexer that Absinthe uses (Leex, part of Erlang/OTP), column tracking isn’t available... yet. For the moment, to be compatible with client tools, Absinthe always reports the column value as 0 (fixed now ?)

rather than returning errors in GraphQL’s free-form, errors portion of the result, it might make sense to model our errors as normal data—fully defining the structure of our errors as normal types to support introspection and better integration with clients

```elixir
mutation do
  field :create_menu_item, :menu_item do
    # Contents
  end
end
```

diagram the relationship between the resulting GraphQL types and fields

instead of returning the menu item directly, our mutation field returned an object type, :menu_item_result, that would sit in the middle

```elixir
object :menu_item_result do
  field :menu_item, :menu_item
  field :errors, list_of(:input_error)
end
```

This result models each part of the output, the menu item and the errors. The :errors themselves are an object, which we’ll put in the schema because they’re generic enough to be used in a variety of places

```elixir
@desc "An error encountered trying to persist input"
object :input_error do
  field :key, non_null(:string)
  field :message, non_null(:string)
end
```

how the resulting GraphQL type structure would look like, once we modified the mutation field to declare its result to be a :menu_item_result

```elixir
case Menu.create_item(params) do
  {:error, changeset} ->
    {:ok, %{errors: transform_errors(changeset)}}
  {:ok, menu_item} ->
    {:ok, %{menu_item: menu_item}}
end
```

regardless of error state, an `:ok` tuple is returned; it’s just doing the work of translating database errors into values that can be transmitted back to clients

GraphQL documents from the clients wouldn’t look much different; they’d just be a level deeper

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

can interpret the success of the result by checking the value of `menuItem` and/or `errors`, then give feedback to users appropriately

Because the errors are returned as result of specific fields, this means that, even in cases where the client sends multiple mutations in a single document, any errors encountered can be tied to the specific mutation that failed

users don’t need to know the structure of your errors ahead of time, or if you don’t think supporting introspection for documentation purposes is worth it, even this basic modeling is overkill; just return simple `:error` tuples instead. They’re low ceremony and flexible enough to support most use cases
