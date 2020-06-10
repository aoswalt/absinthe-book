# Chapter 11: Integrating with the Frontend

The two most popular approaches to using GraphQL from JavaScript today: Relay (the original GraphQL framework) and Apollo Client (p. 221)

## Starting Simple

### Fetching a GraphQL Query

a completely normal `HTTP` `POST` (p. 225)

```JavaScript
function fetchMenuItems() {
  return window.fetch('http://localhost:4000/api', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      query: '{ menuItems { name } }'
    })
  }).then(response => response.json())
}
```

we could be using `GET`, but it's easier and more consistent to encode our GraphQL document as part of an `application/json` `POST` body (p. 225)

### Configuring for CORS

You can use mutation operations just as easily from an `HTTP` `POST` (p. 229)

To use subscription operations, however, we're going to need to add some additional dependencies (Would a socket library work?) (p. 229)

## Choosing a Framework

There are two major client-side JavaScript frameworks that developers use to build user interfaces on top of GraphQL: Relay and the Apollo GraphQL platform (p. 229)

Relay is the original project that illustrated the use of GraphQL, released by Facebook at the same time in 2015, although it's progressed quite considerably since then. While the Apollo Platform is, effectively, a collection of related tools and product offerings built around GraphQL, Relay is the more prescriptive, opinionated framework for building GraphQL-based web applications with React (p. 230)

Relay sets certain additional expectations about the way you've built your GraphQL schema, and supports some out-of-the-box patterns (like pagination) as a benefit of adhering to those constraints (p. 230)

Originating from the Meteor Development Group, Apollo is a large set of open source packages, projects, and tools that work in concert to provide a GraphQL client framework - a more ala carte approach than Relay (p. 230)

## Using Apollo Client

### Wiring in GraphQL

The `@absinthe/socket-apollo-link` package, an officially supported Absinthe JavaScript package that's custom-built to add support for Absinthe's use of Phoenix websockets and channels (p. 234)

the Absinthe websocket configuration (p. 235)

```javascript
import * as AbsintheSocket from "@absinthe/socket"
import { createAbsintheSocketLink } from "@absinthe/socket-apollo-link"
import { Socket as PhoenixSocket } from "phoenix"

export default createAbsintheSocketLink(AbsintheSocket.create(
  new PhoenixSocket("ws://localhost:4000/socket")
))
```

the base socket definition that `@absinthe/socket` provides, a utility function that knows how Apollo needs the socket to behave, and the underlying Phoenix socket code (p. 235)

client configuration (p. 236)

```javascript
import ApolloClient from "apollo-client"
import { InMemoryCache } from "apollo-cache-inmemory"

import absintheSocketLink from "./absinthe-socket-link"

export default new ApolloClient({
  link: absintheSocketLink,
  cache: new InMemoryCache()
})
```

instantiate our client, providing the link and cache options (p. 236)

Apollo Client doesn't know anything about React directly. A specialized package, `react-apollo`, provides the necessary integration features (p. 236)

graphql-tag, used to define GraphQL documents in our application code (p. 236)

make use of our brand new GraphQL client (p. 236)

```javascript
import { ApolloProvider } from 'react-apollo'
import client from './client'

ReactDOM.render(
  <ApolloProvider client={client}>
    <App />
  </ApolloProvider>,
  document.getElementById('root')
)
```

define the GraphQL query for the menu items and use `react-apollo` `graphql()` function to build it into a higher order component that wraps the App component (p. 237)

```javascript
get menuItems() {
  const { data } = this.props
  if (data && data.menuItems) {
    return data.menuItems
  } else {
    return []
  }
}
```

```javascript
const query = gql`
  { menuItems { id name } }
`

export default graphql(query)(App)
```

you don't need to deal with the GraphQL request, and the result from our API is provided to the `App` component automatically as React properties (p. 237)

the addition of `__typename` to our GraphQL query. This is done automatically by Apollo to help facilitate client-side caching, which is done by type (p. 238)

requests being sent across the websocket (p. 238)

we want to use normal HTTP requests for non-subscription related operations (p. 239)

### Using a Hybrid Configuration

Giving our GraphQL client the ability to talk HTTP/S requires us to pull in another dependency, `apollo-link-http` (p. 239)

use a special function, `ApolloLink.split()` to configure when each transport method should be used (p. 240)

```javascript
import ApolloClient from "apollo-client"
import { InMemoryCache } from "apollo-cache-inmemory"
import { ApolloLink } from "apollo-link"
import { createHttpLink } from "apollo-link-http"
import { hasSubscription } from "@jumpn/utils-graphql"
import absintheSocketLink from "./absinthe-socket-link"

const link = new ApolloLink.split(
  operation => hasSubscription(operation.query),
  absintheSocketLink,
  createHttpLink({uri: "http://localhost:4000/api/graphql" })
)

export default new ApolloClient({
  link,
  cache: new InMemoryCache()
})
```

The `hasSubscription()` function, from one of `@absinthe/sockets`'s dependencies, is a handy utility that lets us check our GraphQL for a subscription. In the event one is found, we use our websocket link. Otherwise we send the request over HTTP to the configured URL (p. 240)

### Using Subscriptions

another subscription field to our GraphQL schema - this time so our user interface is notified when new menu item is added (p. 240)

```elixir
field :new_menu_item, :menu_item do
  config fn _args, _info ->
    {:ok, topic: "*"}
  end
end
```

At the bottom of `App.js`, we'll define the subscription and add some configuration to the `graphql()` higher order component to handle sending the subscription document and inserting any new menu items that are received (pp. 241-242)


```javascript
const query = gql`
  { menuItems { id name } }
`
const subscription = gql`
  subscription {
    newMenuItem { id name }
  }
`

export default graphql(query, {
  props: props => {
    return Object.assign(props, {
      subscribeToNewMenuItems: params => {
        return props.data.subscribeToMore({
          document: subscription,
          updateQuery: (prev, { subscriptionData }) => {
            if (!subscriptionData.data) {
              return prev
            }

            const newMenuItem = subscriptionData.data.newMenuItem

            return Object.assign({}, prev, {
              menuItems: [newMenuItem, ...prev.menuItems]
            });
          }
        })
      }
    });
  }
})(App);
```

defining a function, `subscribeToNewMenuItems()` on line 14, which uses `subscribeToMore()` to send our subscription - and update the components properties with `updateQuery()` (p. 242)

calls the `subscribeToNewMenuItems()` function we defined, which kicks off our subscription (p. 242)

```javascript
componentWillMount() {
  this.props.subscribeToNewMenuItems()
}
```

manually invoke our subscription publishing (p. 242)

```elixir
Absinthe.Subscription.publish(
  PlateSlateWeb.Endpoint,
  %{id: "stub-new-1", name: "New Menu Item"},
  new_menu_item: "*"
)
```

## Using Relay

more opinionated, pre-packaged GraphQL framework for your application, Relay is the gold standard. With an API that's been re-imagined since its initial release in 2015 (p. 243)

The `react-relay` package provides the runtime features that Relay needs to interact with the React UI framework, while `relay-compiler` and `babel-plugin-relay` include development utilities that are used to prepare GraphQL queries, schemas, and related tooling for Relay's use (p. 244)

GraphQL transpiling support that Relay needs (p. 244)

the `@absinthe/socket-relay` package (p. 244)

a Relay Environment, which is how the framework bundles together the configuration that it needs to operate (p. 245)

```javascript
import { createFetcher, createSubscriber } from "@absinthe/socket-relay"
import {
  Environment,
  Network,
  RecordSource,
  Store
} from "relay-runtime"
import absintheSocket from "./absinthe-socket"

export default new Environment({
  network: Network.create(
    createFetcher(absintheSocket),
    createSubscriber(absintheSocket)
  ),
  store: new Store(new RecordSource())
});
```

lets us set up Relay cache storage and network-handling the way we want (p. 245)

configure the websocket itself in another file (p. 245)

```javascript
import * as AbsintheSocket from "@absinthe/socket"
import { Socket as PhoenixSocket } from "phoenix"

export default AbsintheSocket.create(
  new PhoenixSocket("ws://localhost:4000/socket")
)
```

Our Relay application is configured, but it needs to have a static copy of the schema it will be using - the PlateSlate schema - in a format that the Relay compiler can understand (p. 245)

utility, `get-graphql-schema` to grab it from our API using introspection (mix command now) (p. 245)

Relay's `QueryRenderer`, which takes the environment we've defined, our query (constructed using the `graphql()` function), and the logic to run based on the result of executing the query (p. 246)

```javascript
import React, { Component } from 'react'
import { QueryRenderer, graphql } from 'react-relay'
import environment from './relay-environment'

const query = graphql`
  query AppQuery { menuItems { id name } }
`

class App extends Component {
  renderMenuItem(menuItem) {
    return (
      <li key={menuItem.id}>{menuItem.name}</li>>
    )
  }

  render() {
    return (
      <QueryRenderer
        environment={environment}
        query={query}
        render={({error, props}) => {
          if (error) {
            return (
              <div>{error.message}</div>
            )
          } else if (props) {
            return (
              <ul>
                {props.menuItems.map(this.renderMenuItem)}
              </ul>
            )
          } else {
            return (
              <div>Loading...</div>
            )
          }
        }}
      />
    )
  }
}

export default App
```

the query we use here needs to have the operation name `AppQuery`, because that's what the Relay compiler will expect (the name of the component, which is `App`, followed by the type of operation, `Query` (p. 247)

run the compiler to extract our query and prepare a generated copy (p. 247)

add an entry to "scripts" (p. 247)

```json
  "compile": "relay-compiler --src ./src --schema ./schema.graphql"
```

use the new script entry (p. 247)

```sh
yarn compile relay-compiler --src ./src --schema ./schema.graphql
```
```
Created:
- AppQuery.graphql.js
```

built a new file, `AppQuery.graphql.js` and put it in a new directory, `src/__generated__` (p. 247)

inside the file, you'll see something like this (p. 247)

```javascript
  "text": "query AppQuery {\n menuItems {\n id\n name\n }\n}\n"
};

module.exports = batch;
```

### Adding a Subscription

Adding a subscription to a client-side Relay application involves packaging up the actual GraphQL subscription operation with a configuration that defines how it's requested and how data should be interpreted when it's received (p. 248)

add our subscription in a new directory, `src/subscriptions`, and call it `NewMenuItemSubscription` (p. 248)

```javascript
import { graphql, requestSubscription } from 'react-relay'
import environment from '../relay-environment'

const newMenuItemSubscription = graphql`
  subscription NewMenuItemSubscription {
    newMenuItem { id name }
  }
`

export default () => {
  const subscriptionConfig = {
    subscription: newMenuItemSubscription,
    variables: {},
    updater: proxyStore => {
      // Get the new menu item
      const newMenuItem = proxyStore.getRootField('newMenuItem')
      // Get existing menu items
      const root = proxyStore.getRoot()
      const menuItems = root.getLinkedRecords('menuItems')
      // Prepend the new menu item
      root.setLinkedRecords([newMenuItem, ...menuItems], 'menuItems')
     },
     onError: error => console.log(`An error occured:`, error)
  }

  requestSubscription(
    environment,
    subscriptionConfig
  )
}
```

The file defines the subscription and couples it with an updater, which gets the reference to the new menu item in the cache and adds it to the menu item list. It provides a function that will request the subscription using requestSubscription. (p. 248)

use that function from our App component (p. 249)

```javascript
import NewMenuItemSubscription from './subscriptions/NewMenuItemSubscription'

class App extends Component {
  componentDidMount() {
    NewMenuItemSubscription();
  }

  // rest of component
}
```

need to remember to compile our subscription. We use `yarn compile` again. It's smart enough to only compile the new pieces of GraphQL (p. 249)

### Supporting Relay Nodes

To support refetching records from a GraphQL server, Relay has certain expectations about the way records are identified and can be retrieved. Absinthe ships specialized support for the Node pattern as part of the `absinthe_relay` Elixir package (p. 250)

To add `Node` support in our schema, we need to do three things:
* Define a new interface, `:node`, that declares an `:id` field
* Implement the `:node` interface in any object type we'd like to use it
* Define a root-level query field, `:node`, that can fetch any implementing object type records by `:id`
All of these can be done with a single macro: `node`. (p. 251)

modifying our schema (p. 251)

```elixir
use Absinthe.Relay.Schema, :modern
```

the special `:modern` argument that indicates we're targeting Relay v1 (Modern) client applications (p. 251)

In future versions of `absinthe_relay`, the :modern argument to use `Absinthe.Relay.Schema` won't be necessary, as it will default without warnings. For the moment, be explicit and set :modern (or `:classic,` if you're supporting an older application) (p. 251)

the `:node` interface here in the main schema file using the node macro. It's almost identical to a normal use of `interface`; we don't have to provide a name or any of the field details, but we do need to tell Absinthe how to map records to the specific type of object by providing a `resolve_type` function (p. 251)

```elixir
node interface do
  resolve_type fn
    %PlateSlate.Menu.Item{}, _ ->
      :menu_item
    _, _ ->
      nil
  end
end
```

This will create an interface, `:node` that expects one field, `:id`, to be defined - and that the ID will be a global identifier. The fact the ID needs to be a global identifier makes sense, since the node `field` we'll be adding will need to look up any node object (p. 251)

configure our menu item object type as a node (p. 252)

use the `node` macro again, this time as `node object`. We'll edit our menu types file and make the change to our `:menu_item` type (p. 252)

```elixir
use Absinthe.Relay.Schema.Notation, :modern

# Other definitions

  node object :menu_item do
    # Rest of definition, with the :id field removed!
  end
```

removed the `:id` field from the object definition, since the node macro will create one for us - with support for generating global IDs (p. 252)

By default, the IDs are base64-encoded versions of the object type name and the local (database) ID (p. 252)

In practice, Absinthe uses a special function, `Absinthe.Relay.Node.from_global_id/2`, which checks the ID against the schema (pp. 252-253)

```elixir
iex> Absinthe.Relay.Node.from_global_id("TWVudUl0ZW06NA==", PlateSlateWeb.Schema)
  {:ok, %{id: "4", type: :menu_item}}
```

our `node` field; the third and final piece that we need to add to support Relay's refetching (p. 253)

use `from_global_id/2` on the argument it's given and execute a resolver function we provide (p. 253)

```elixir
query do
  node field do
    resolve fn
      %{type: :menu_item, id: local_id}, _ ->
        {:ok, PlateSlate.Repo.get(PlateSlate.Menu.Item, local_id)}
      _, _ ->
        {:error, "Unknown node"}
    end
  end
  # Other query fields
end
```

Because the IDs are already parsed for us, we just needed to match against the result. At the moment we're handling menu items, but we could expand this to match other node types (p. 253)

to support any other node types, we just need to: (p. 254)
* Expand the `:node` interface `resolve_type` match
* Make sure the object definition uses the node macro and doesn't define its own `:id` field
* Expand the `:node` query field's argument match for parsed IDs

Passing opaque global IDs back to your client applications obviously means that they're going to be using those IDs in any subsequent queries, mutations, and subscriptions. To help handle these global IDs transparently, even when nested in arguments, Absinthe provides a piece of middleware, `Absinthe.Relay.Node.ParseIDs`. (p. 254)

### Supporting Relay Conenctions

To support pagination, Relay has defined a set of conventions used to model lists of records and the related metadata (p. 254)

![Simple menuItems](../images/ch11_simple-menuitems.png "Simple menuItems")

the root query type has a field, `menuItems` (or `:menu_items`, in Absinthe's Elixir parlance) that returns a list of `MenuItem` (that is, `:menu_item`) records (p. 254)

![menuItems Relay Connection](../images/ch11_menuitems-relay-connection.png "menuItems Relay Connection")

the addition of two new object types: (p. 255)
* `MenuItemConnection`, an object type that contains the edges and the `pageInfo` fields
* `MenuItemEdge`, an object type modeling a single node result (the actual data), and its placement in the list

makes use of a statically-defined type, `PageInfo`, with important paging information like `hasNextPage` and `hasPreviousPage` (p. 255)

field would need to accept some new arguments (`first` and `since` for forward pagination, `last` and `before` for backward pagination). (p. 255)

Relay connection pagination is cursor-based, meaning that it's all about retrieving a number of records `since` or `before` a given (optional) cursor value. Every connection edge has a cursor. (p. 255)

convert it to a full-blown Relay connection field. We're going to be using the `connection` macro (p. 256)

```elixir
use Absinthe.Relay.Schema, :modern
  # Rest of schema

  query do
    # Other query fields

    connection field :menu_items, node_type: :menu_item do
      arg :filter, :menu_item_filter
      arg :order, type: :sort_order, default_value: :asc
      resolve &Resolvers.Menu.menu_items/3
    end
  end
```

changed the `:menu_items` field by prefixing it with connection and, instead of declaring that it's of type `list_of(:menu_item),` we declare a `:node_type`. The `connection` macro uses this node type to infer the name of the associated connection type (p. 256)

the `:filter` and `:order` arguments were left untouched. While the `connection` macro automatically adds the pagination-related arguments for you, it doesn't get in the way of custom arguments that you might want (and we do) for your queries (p. 256)

changes that are necessary in our menu types file; pulling in the `connection` macro from `Absinthe.Relay.Schema.Notation` and using it to define our connection type, tied to the `:menu_item` node type (p. 256)

```elixir
use Absinthe.Relay.Schema.Notation, :modern

# Other definitions

  connection node_type: :menu_item
```

You can customize the contents of the connection if you like (by providing a `do` block and the usual use of the `field` macro), but ours is just a vanilla connection with the usual `node` and `pageInfo` trappings, so we can leave it as a single line (p. 256)

field resolver, since we need to describe how the query will be executed (p. 257)

```elixir
def menu_items(_, args, _) do
  Absinthe.Relay.Connection.from_query(
    Menu.items_query(args),
    &PlateSlate.Repo.all/1,
    args
  )
end
```

we want to use `Absinthe.Relay.Connection`'s useful `from_query/4` function to handle the actual pagination of records and construction of a valid `:menu_item_connection` result (p. 257)

Instead of returning the result of the database query, this returns the query itself (an `Ecto.Queryable.t`, to be precise), which `from_query/4` uses (along with the repository function and the arguments) to take care of matters for us

changes to the behavior of `Menu.items_query/1` to be public and gracefully handle additional arguments that it doesn't use (p. 257)

```elixir
_, query ->
  query
```

If you like Relay's take on global identification or record pagination, but don't want to use Relay itself, never fear. You can still make use of the `absinthe_relay` package on the server-side with whatever client-side system that you want. While things might not work as transparently as they would with Relay, at the end of the day it's just GraphQL in and JSON out (p. 258)
