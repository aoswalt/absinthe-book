# Chapter 2: Building a Schema

The schema is used by GraphQL servers as the canonical source of information when deciding how to respond to a request

## Our Schema Module

GraphQL schema, which defines its domain model and how data is retrieved

clients of our API accessing a list of menu items. An example query from a client might look something like this:
```graphql
{
  menuItems {
    name
  }
}
```

If the user was talking to us, this would translate to “Give me the names of all of the menu items that you have.” Here’s a sample of the type of JSON they’d expect in response:
```json
{
  "data": {
    "menuItems": [
      { "name": "Reuben" },
      { "name": "Croque Monsieur" },
      { "name": "Muffuletta" }
    ]
  }
}
```

To make this happen, we need to define a GraphQL object type for our menu items

All data in GraphQL has an associated type

Our menu item type is wat GraphQL refers to as an object, since it contains a number of fields (like name

your API and the underlying data representations do not need to be identical, or even have the same structure. One of the main values in modeling GraphQL types is that they can serve as an abstraction

the beginnings of the schema module, with the boilerplate for our new menu item type. You can see we’re also stubbing out the query definition for now (more on that soon):

```elixir
defmodule PlateSlateWeb.Schema do
  use Absinthe.Schema

  query do
    # Ignore for now
  end

  object :menu_item do
    # adding fields soon
  end
end
```

Absinthe models the types that we define as Elixir structs

identifier The internal identifier Absinthe uses to refer to this type. As we define the schema, we’ll be using it a lot, too

description Documentation we can provide for an object type that will be automatically available to API users using GraphQL’s built-in introspection features

name The canonical GraphQL type name. While required, this will be automatically generated for you if you don’t provide it yourself, based on the Absinthe identifier

fields The real meat and potatoes of our object types

is_type_of and interfaces Support GraphQL’s Union and Interface abstract types (ch 4)

### Adding Fields

Adding a field to an object type is as simple as using the field macro. The macro takes an identifier atom, a type reference, an optional keyword list of attributes, and a further optional block for more in-depth configuration

We’ll start with the basics, and add :id, :name, and :description fields to our :menu_item object:
```elixir
object :menu_item do
  field :id, :id
  field :name, :string
  field :description, :string
end
```

The identifiers that we’ve chosen for the fields will give the fields canonical GraphQL names of "id", "name", and "description". (Like object types, the canonical GraphQL names of fields are automatically generated for us

The second argument to the field macro here defines the field type

## Making a Query

A GraphQL query is the way that API users can ask for specific pieces of information

to support users getting menu items, we need to provide two things: A way for the user to request objects of the type A way for the system to retrieve (or resolve) the associated data

The key to the first objective is defining a special object type to serve as the entry point for queries on a GraphQL schema. We already defined it when we used the query macro earlier

The query macro is just like object, but it handles some extra defaults for us that Absinthe expects

there’s nothing special about the root query object type structurally. Absinthe will use it as the starting point of queries, determining what top-level fields are available

list_of is a handy Absinthe macro that we can use to indicate that a field returns a list of a specific type's shorthand for %Absinthe.Type.List{of_type: :menu_item}. That’s a little long to type every time you need to return a list

Absinthe handles translating between these two conventions automatically so that both the client and the server can work using the formats most familiar to them. The functionality is extensible, too; if you want to use a different naming convention in your GraphQL documents, you can

we have to retrieve the data for the field. GraphQL refers to this as resolution, and it’s done by defining a resolver for our field

A field’s resolver is the function that runs to retrieve the data needed for a particular field
```elixir
query do
  field :menu_items, list_of(:menu_item) do
    resolve fn
      _, _, _ -> {:ok , Repo.all(Menu.Item)}
    end
  end
end
```

Because the field doesn’t need any parameters, we’re ignoring the function arguments and just returning an :ok tuple with the list of menu items. That lets Absinthe know that we were able to resolve the field successfully

You don’t need to define a resolver function for every field

If a resolver is not defined for a field, Absinthe will attempt to use the equivalent of Map.get/2 to retrieve a value from the parent value in scope, using the identifier for the field

Resolution starts at the root of a document and works its way deeper, with each field resolver’s return value acting as the parent value for its child fields

Because the resolver for menuItems (that is, the resolver we defined in our schema for the :menu_items field) returns a list of menu item values—and resolution is done for each item in a list—the parent value for the name field is a menu item value

something very close to:
```elixir
  for menu_item
```

## Running Our Query with GraphiQL

GraphiQL is "an in-browser IDE for exploring GraphQL"

three versions of GraphiQL; the official interface[10], an advanced version[11], and GraphQL Playground -- explorer not included

setting up two routes: "/api" with the regular Absinthe.Plug, and "/graphiql" with the GraphiQL plug. The former is what API clients would use and what we’ll use in our tests, and then the latter provides the “in-browser” IDE

simplified, official GraphiQL interface, set with the interface: :simple option

GraphiQL helpfully suggested some autocompletions? That’s because when we loaded the page, it automatically sent an introspection query to our GraphQL API, retrieving the metadata it needs about PlateSlateWeb.Schema to support autocompletion and display documentation

able to specify additional fields in our query without having to modify the schema any further

"Docs" link that, when clicked, will open up a new sidebar full of API documentation

we can add a :description value as part of the third argument to the field macro:
```elixir
field :menu_items, list_of(:menu_item), description: "The list of available items on the menu" do
  # Menu item field definition
end
```

another technique we can use to add descriptions, using a module attribute, @desc, just as you would with Elixir’s @doc:
```elixir
@desc "The list of available items on the menu"
field :menu_items, list_of(:menu_item) do
  # Menu item field definition
end
```

the latter approach supports multi-line documentation more cleanly and sets itself off from the working details of our field definitions

## Testing Our Query

just as we would a Phoenix controller, using the PlateSlate.ConnCase helper module

passes the @query module attribute we defined above (making use of Elixir’s handy multi-line """ string literal) as the :query option, which is what Absinthe.Plug expects

response is then checked to make sure that it has an HTTP 200 status code and includes the JSON data that we expect to see
