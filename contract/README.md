# Bridge Contracts

In this folder there are 3 different options for the bridge contract:


### bridge-1.lua

This version of the bridge contract is designed to be called by the router

The user cannot directly transfer the tokens to the bridge contract

Problem: native tokens are not supported


### bridge-2.lua

This version of the bridge contract can receive tokens from the user

But it is the router/contract owner that will call the token contract to burn the tokens


### bridge-3.lua

This version of the bridge contract can receive tokens from the user

When the user sends the tokens to the bridge contract, it will either burn or lock the tokens (according to the source) and emit an event
