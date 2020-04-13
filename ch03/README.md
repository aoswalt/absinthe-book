# Chapter 3: Taking User Input

GraphQL takes a more declarative approach however, by defining input as part of your API schema and supporting type validations as a core feature

allowing our Elixir application code to focus on more core application concerns. This will make our code more readable and easier to maintain

GraphQL’s most fundamental user input concept, the field argument

## Defining Field Arguments

GraphQL documents are made up of fields

GraphQL has the concept of field arguments; a way for users to provide input to fields that can be used to parameterize their queries

the field’s resolver just returns all the menu items

add an argument to our schema to support filtering menu items by name. We’ll call it matching

```elixir
field :menu_items, list_of(:menu_item) do
  arg :matching, :string
  resolve fn
    _, %{matching: name}, _ when is_binary(name) ->
      query = from t in Menu.Item, where: ilike(t.name, ^"%#{name}%")
      {:ok , Repo.all(query)}
    _, _, _ ->
      {:ok , Repo.all(Menu.Item)}
  end
end
```

not making the matching argument mandatory here, so we need to support resolving our menuItems field in the event it’s provided, and in the event it isn

Absinthe only passes arguments to resolvers if they have been provided by the user. Making a map key match of the arguments resolver function parameter is a handy way to check for a field argument that’s been specified in the request

Writing complicated resolvers as anonymous functions can have a negative side-effect on a schema’s readability

extract the resolver into a new module

Because filtering menu items is an important feature of our application—and could be used generally, not just from the GraphQL API—we’ll also pull the core filtering logic into the PlateSlate.Menu module, which is where our business logic relating to the menu belongs

new resolver module: 03-chp.userinput/3-matching/lib/plate_slate_web/resolvers/menu.ex

```elixir
defmodule PlateSlateWeb.Resolvers.Menu do
  alias PlateSlate.Menu

  def menu_items(_, args, _) do
    {:ok, Menu.list_items(args)}
  end
end
```


it’s important to set up a solid separation of concerns early on in our project

a resolver’s job is to mediate between the input that a user sends to our GraphQL API and the business logic that needs to be called to service their request

```elixir
query do
  field :menu_items, list_of(:menu_item) do
    arg :matching, :string
    resolve &Resolvers.Menu.menu_items/3
end
```


## Providing Field Argument Values

There are two ways that a GraphQL user can provide argument values for an argument: as document literals, and using variables

Using document literals, values are directly embedded inside the GraphQL document. It’s a straightforward approach that works well for static documents

HTTP 400 response code from Absinthe. This indicates that one or more errors occurred that prevented query execution

API can respond appropriately to user-provided values, without any intervention by any custom type-checking code

If the frontend application only used document literals, it would need to interpolate the search terms directly into the GraphQL document. For each user request, a completely new document would have to be generated, likely using string interpolation

ensuring that the GraphQL document wouldn’t be malformed

no double quotes were provided that would prematurely end the string value and cause a parse error from the GraphQL server

GraphQL variables, a way to insert dynamic argument values provided alongside (rather than inside) the static GraphQL document

GraphQL variables act as typed placeholders for values that will be sent along with the request

parameterized SQL queries for insertion and sanitization of values

GraphQL variables are declared with their types—before they’re used—alongside the operation type

A GraphQL document consists of one or more operations, which model something that we want the GraphQL server to do. Up to this point, we’ve been asking the server to provide information, an operation that GraphQL calls a query. GraphQL has other operation types too, notably mutation for persisting a change to data, and subscription to request a live feed of data

GraphQL assumes that if you’re providing a single operation like this, its operation type is query

when we’re using variables, we need to use the more formal, verbose syntax and fully declare the operation

Variable declarations are provided directly before the curly braces that start the body of an operation, and are placed inside a set of parenthesis. Variable names start with a dollar sign ($), and their GraphQL types follow after a colon (:) and a space character. If we were declaring multiple variables, we’d list them separated by commas

The variable’s GraphQL type isn’t the snake_cased form as declared in our schema

In GraphQL documents, however, we need to use the canonical GraphQL type names (like String) which are CamelCased

allows the GraphQL server to give clearer error messages about the expected versus provided variable value and lets the GraphQL document writer make values mandatory to support client-side validation

Variable values are provided alongside GraphQL documents

```elixir
get(build_conn(), "/api", query: @query, variables: @variables
```

passing the value of term (without the $ prefix) along in variables

using a GET request here, but a POST would also work

the value of variables should be JSON-encoded

## Using Enumeration Types

A GraphQL enumeration (or enum, as it’s generally called) is a special type of scalar that has a defined, finite set of possible values

Enums are a good choice if the possible values are well-defined and unlikely to change

The enum macro works just like object, but it defines an enumeration instead of an object

The value macro defines a possible value of the enum

```elixir
enum :sort_order do
  value :asc
  value :desc
end

arg :order, :sort_order
```


the standard form for an argument declaration is arg NAME, TYPE

we can make the type more explicit by providing it as a :type option

The second argument to the arg macro can be a keyword list to support additional options

```graphql
{
  menuItems(order: DESC) {
    name
  }
}
```
"""


providing the order as DESC, and without quotes

By convention, enum values are passed in all uppercase letters; the value macro that we used to declare the enum values sets up a mapping for us, accepting enum values as literals and variables in all uppercase and converting them to atoms automatically

While the value macro does support customizing the external representation used for enum values, the GraphQL Specification explicitly recommends the uppercase convention that Absinthe sets up for you automatically

it ends in an exclamation mark (!). This denotes that, as the person writing the GraphQL query document, you’re making the variable mandatory

A document that doesn’t meet its variable requirements won’t be executed if it’s received by Absinthe, and some client side frameworks even enforce variable checks to prevent inadequately filled GraphQL documents from being sent at all

We can make arguments mandatory at the schema level as well, adding non-null constraints to our argument types

## Modeling Input Objects

various flags and options that would be better organized into related groupings. GraphQL gives us a tool to do this: input object types. We can collect multiple arguments and model them as a special object type that’s used just for argument values

```elixir
@desc " Filtering options for the menu item list"
input_object :menu_item_filter do
  @desc "Matching a name"
  field :name, :string
  @desc "Matching a category name"
  field :category, :string
  @desc "Matching a tag"
  field :tag, :string
  @desc "Priced above a value"
  field :priced_above, :float
  @desc "Priced below a value"
  field :priced_below, :float
end
```

not using arg any more; just like normal object types, input objects model their members as fields, not arguments

Fields for input objects, however, don’t have any arguments (or a resolver) of their own; they’re merely there to model structure

```elixir
arg :filter, :menu_item_filter
```

}
```graphql
menuItems(filter: {category: "Sandwiches", tag: "Vegetarian"}) {
```


providing the filter argument value formatted just as you might expect from a JavaScript object, using curly braces and bare, unquoted identifiers for the field names

Here are some things to keep in mind when building input objects. Input objects can be nested. You can define a input object field as having an input object type. This nesting can be arbitrarily deep. Input object types, unlike normal object types, do not support circular references. You can’t have two input types that refer to each other, either directly or through an intermediary. Input object type fields can be of any type that a field argument might use. It’s best to just think of them as structured arguments

## Marking Arguments as Non Null

```graphql
query ($filter: MenuItemFilter!) {
  menuItems(filter: $filter) {
    name
  }
}
```

The document here declares that the $filter variable is a MenuItemFilter, while the addition of an exclamation mark denotes that a value is mandatory. This is a constraint that the document designer (usually a frontend developer) builds into the query

ensure that a filter was always provided to the :menu_items field, regardless of what the document says should be mandatory. We can do this by using the Absinthe non_null macro, wrapping the argument type

sending an empty filter object is enough to count as meeting this constraint; to force values in the filter, we’d have the flexibility to handle those directly

could also mark that field as non-nullable:

```elixir
input_object :menu_item_filter do
  field :category, non_null(:string)
  field :tag, :string
  field :priced_above, :float
  field :priced_below, :float
end
```

Non-nullability for input object fields means the client needs to provide a non-null value as part of the request. Non-nullability for output object fields means the server needs to provide a non-null value as part of the response

Dealing with Dependent Arguments You may encounter situations where you’ve defined many arguments for a field only to discover that certain arguments should be non-nullable—but only in the event another argument isn’t present—or is. Here are two differing solutions that you can evaluate: Make the field arguments more complex: try grouping arguments that go together into input objects, like we did with menu item filtering. This lets you leave the input object nullable but individual input object fields as non-nullable. Sometimes it’s more important to keep a field cohesive. Make the field simpler: split it into multiple, simpler fields that handle narrower use cases, and have their own documentation (via @desc). Don’t be afraid to create more, case-specific fields, each with a narrow focus. You can always share resolution logic and output types

## Creating Your Own Scalar Types

Scalar types form the leaves of your input and output trees

Absinthe’s’ built-in scalar types, from :integer to :string and :id, all have a firm grounding in the GraphQL specification

by just making the :added_before argument a :string field. The problem though would be that our resolver code would have to go through the effort of parsing that string into an actual %Date{} struct, and handling any errors that might show up if it’s in an invalid format. We also lose out on documentation because while the field type will say string, it’s really more specific than that

the scalar type itself, which we can build with the scalar macro

Each scalar needs to have two parts defined for it, a parse function and a serialize function. parse converts a value coming from the user into an Elixir term (or returns :error) serialize converts an Elixir term back into a value that can be returned via JSON

Scalars can be used as both input and output types

why we do input.value in our parse function instead of just input. The input for our parse function isn’t just the string "2017-01-31" but rather a struct that holds additional information about our input

We can use the extra information provided by the input struct to handle these cases nicely, checking the type of the input that was provided

```elixir
with %Absinthe.Blueprint.Input.String{value: value} <- input,
 {:ok, date} <- Date.from_iso8601(value) do
    {:ok, date}
else
  _ ->:error
end
```

Instead of accepting any input type, we are pattern matching for string inputs so that we can make sure to give the date parsing function acceptable input. If we didn’t do this, Date.from_iso8601/1 would raise an exception

Absinthe ships with a number of custom scalar definitions, including several for dates and times. You can find these definitions in Absinthe.Type.Custom
