# Bridge Contracts

In this folder there are 3 different options for the bridge contract

The difference between them is mainly on how the `swapout` is implemented


### bridge-1

This version of the bridge contract is designed to be called by the router

The user cannot directly transfer the tokens to the bridge contract

The router will call the proper `swapout` function to either burn or lock the user tokens

Limitation: native tokens are not supported


### bridge-2

This version of the bridge contract can receive tokens directly from the user

The user transfer tokens to the bridge contract with some additional parameters (`to_chain` and `to_address`)

But it is the router that will call the token contract to burn the tokens


### bridge-3

This version of the bridge contract can receive tokens directly from the user

The user transfer tokens to the bridge contract with some additional parameters (`to_chain` and `to_address`)

When the user sends the tokens to the bridge contract, it will either burn or lock the tokens (according to the source) and emit an event

The router can then act accordingly

This contract also supports many tokens, so it can be used as a single bridge contract linked to many (input and output) tokens
