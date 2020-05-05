# Chapter 6: Going Live with Subscriptions

such connections don’t fit into the REST API paradigm very easily

GraphQL, on the other hand, puts near real-time data at the same, first-class level as queries or mutations with what are called subscription operations

subscriptions that allow users to request data updates—using the same semantics as any other GraphQL request—and manage the lifecycle of the data feed

## Setting up Subscriptions

Subscriptions let a client submit a GraphQL document which, instead of being executed immediately, is instead executed on the basis of some event in the system

add an Absinthe.Subscription supervisor to the PlateSlate application’s supervision tree

This Absinthe.Subscription supervisor starts a number of processes that will handle broadcasting results, and hold on to subscription documents

You pass it your PlateSlateWeb.Endpoint module because you’re using the Phoenix endpoint as the underlying pubsub mechanism

add a single line to its definition to provide a few extra callbacks that Absinthe expects

Absinthe.Phoenix provides a way to use Absinthe from within Phoenix specific features like Channels

configure our socket

configure GraphiQL to use this socket

## Event Modeling

Subscriptions push data in response to events or actions within your system, so it isn’t enough to think of subscriptions as a purely API-related concern

a model that lets us track the lifecycle of an order as it is started, completed, and ultimately picked up by the customer

Menus change over time, but orders are historical

a JSONB column called items will store a snapshot of each item taken at the time the order is placed

need to modify the create_order context function to actually build snapshots of the order

The idea here is that we pass in the menu items ids that the user wants to order, and then the create_order/1 function itself looks up the price to compute the total and build out the items snapshot

good indicator of what our GraphQL inputs should look like. We’re expecting a list of items that we want to order, as well as an optional customer reference number

the items don’t contain any price info, as that should be always looked up from the menu system (to make sure clients aren’t doing anything funny with the prices

```elixir
field :place_order, :order_result do
  arg :input, non_null(:place_order_input)
  resolve &Resolvers.Ordering.place_order/3
end

input_object :place_order_input do
  field :customer_number, :integer
  field :items, non_null(list_of(non_null(:order_item_input)))
end
```

The non_null(list_of(non_null(:order_item_input))) type we set for the :items field may seem a bit convoluted

The outer most non_null indicates that the client can’t leave out the :items field or make it null. The list_of just tells us that the value will be a list, and then the inner most non_null just tells the client that none of the items in the list can themselves be null

```elixir
def place_order(_, %{input: place_order_input}, _) do
  case Ordering.create_order(place_order_input) do
    {:ok, order} ->
      {:ok, %{order: order}}
    {:error, changeset} ->
      {:ok, %{errors: transform_errors(changeset)}}
  end
end
```

If you need to use values from a query in a subsequent mutation, copy and paste those values into the variables part of GraphiQL, and then reference those variables within your mutation document

GraphiQL expects variable input to be given in JSON format

## Submitting Subscriptions

You’ll first need to define a subscription field in your schema, and then you’ll also need a way to actually trigger this subscription when the :place_order mutation runs

```elixir
subscription do
  field :new_order, :order do
    config fn _args, _info ->
      {:ok, topic: "*"}
    end
  end
end
```

another top level object, subscription, to house our subscription fields

the :new_order which will return the :order object we’re already familiar with. The fact that it returns a regular :order object is crucial, because this means that all the work you have done to support the output of the mutation can be immediately reused for real time data

the config macro, and it’s one of a couple macros that are specific to setting up subscriptions

The job of the config macro is to help us determine which clients who have asked for a given subscription field should receive data by configuring a topic

topics are scoped to the field they’re on, and that they have to be a string

use "*" to indicate that we care about all orders (but there’s nothing special about "*" itself

The config function can also return {:error, reason}, which prevents the subscription from being created

although the server has accepted the subscription document, the server is waiting on some kind of event that will trigger execution of the document and distribution of the result

The most direct way to make this trigger happen is with the Absinthe.Subscription.publish/3 function, which gives us manual control of the publishing mechanism

The arguments to the publish/3 function are the module you’re using as the pubsub, the value that you’re broadcasting, and the field: topic pairs at which to broadcast the value

Unlike a root query or root mutation resolver which generally starts with no root value and has to start from scratch, the root value of a subscription document is the value that is passed to publish/3

one possibility for making our live interface is to put it inside the :place_order mutation resolver so that instead of triggering subscriptions from iex we’ll trigger subscriptions every time a new order is placed

## Testing Subscriptions

you’ll need a similar PlateSlate.SubscriptionCase module for managing the subscription integration tests via channels

This module sets up the socket we’ll use in each of our test cases, and also gives us a convenience function for getting menu items

it’s a lot like testing a GenServer

the test process itself which acts like the client

Testing a socket, then, is just a matter of sending it the data we need to configure our subscription, triggering a mutation, and then waiting for subscription data to get pushed to the test process

the first thing we do is push a "doc" event to the socket along with the parameters specifying our subscription document, and then we assert for a reply from the socket that returns a subscriptionId

a single socket can support many different subscriptions, and the subscriptionId is used to keep track of what data push belongs to what subscription

The next thing we do is run a mutation to place an order

You could actually push this document over the socket as well, sockets support all the different operation types

doing an explicit Absinthe.run call is handy because it helps make it clear that the trigger process that’s happening isn’t tied to the socket process specifically

all we have to do is assert that the test process gets a message containing the expected subscription data

## Subscription Triggers

when we start thinking about tracking the life cycle of a particular entity, we need to pay a lot more attention to how we’re setting up our subscriptions, and how we’re triggering them

The challenge isn’t just keeping track of how the topics are constructed, it can also be hard to make sense of where in your code base publish/3 calls may be happening

We need to complete the lifecycle of an order by providing two mutations, one to indicate that it’s ready, and another to indicate that it was picked up

Subscribing to these events is just a little bit different than before, because now we are trying to handle events for specific orders based on ID

When the client is notified about new orders via a new_order subscription, we then want to give them the ability to subscribe to future updates for each of those subscriptions specifically

we want to use this one subscription field to get updates triggered by both the :ready_order and :complete_order mutation fields

it’s often the case that you just need a single subscription that lets you get all the state changes for a particular entity that you want to watch

in our config function. Here we’re using the arguments provided to the field to generate a topic that is specific to the id of the order we care about

The issue with our approach thus far is that although our schema contains the :place_order mutation and also the :new_order subscription fields, there isn’t any indicator in the schema that these two fields are connected in any way. Moreover, for subscription fields that are triggered by several different mutations, the topic logic is similarly distributed in a way that can make it difficult to keep track of

This pattern of connecting mutation and subscription fields to one another is so common that Absinthe considers it a first class concept and supports setting it as a trigger on subscription fields, avoiding the need to scatter publish/3 calls throughout your code base

```elixir
trigger [:ready_order, :complete_order], topic: fn
    %{order: order} -> [order.id]
    _ -> []
  end
```

The trigger macro takes two arguments, a mutation field name (or list of names) and a set of options that let you specify a topic function. This trigger topic function receives the output of the mutation as an argument, and should return a list of topics that are each used to find relevant subscriptions

each of these documents should only get events that are for the particular order id specified in the arguments

As we noted earlier, topics are always strings, so Absinthe will call to_string/1 on whatever return

Trigger topic functions can specify multiple topics by returning a list: ["topic1", "topic2"]

the mutation resolver can return error information from changesets. When this happens we don’t want to push out anything because the order wasn’t actually updated. Returning [] prevents any publication from happening for this particular mutation, because we aren’t returning any topics that we want to publish to

if the :ready_order and :complete_order mutation fields returned different values? A given subscription field can have many different triggers defined on it, each with a different topic function

we’re using a resolver here, whereas we didn’t need to do so on the other subscription field

we’re getting the full result of the mutation, which in the success case is %{order: order}. The resolver can just pattern match on this to unwrap it

Whether to use an explicit Absinthe.Subscription.publish/3 call or the trigger macro will depend on the scenario

it’s best to use triggers when there’s a clear and sensible mapping of mutations to subscriptions because it helps place this information in a clear and central location

This test case ultimately captures the story we’re going for. You’ve got two distinct subscriptions, and then an update happens to just one of them and that’s the one you get the update for, not any other

GraphQL subscriptions end up being rather simple, because with GraphQL they’re just another part of your normal API
