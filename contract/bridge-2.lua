--[[
  MultiChain Bridge Contract
  This version of the bridge contract can receive tokens from the user
  But it is the router/owner that will call the token contract to transfer the tokens
]]

-- state variables
state.var {
  _owner = state.value(),     -- address
  _paused = state.value(),    -- bool
  _token = state.value(),     -- address
}

function constructor()
  -- set the bridge owner as the contract creator
  _owner:set(system.getCreator())
  -- mark as not paused
  _paused:set(false)
end

-- A internal type check function
-- @type internal
-- @param x variable to check
-- @param t (string) expected type
local function _typecheck(x, t)
  if (x and t == 'address') then
    assert(type(x) == 'string', "the address must be in string format")
    -- check address length
    assert(#x == 52, string.format("invalid address length (%s): %s", #x, x))
    -- check address checksum
    local success = pcall(system.isContract, x)
    assert(success, "invalid address: " .. x)
  elseif (x and t == 'ubig') then
    -- check unsigned bignum
    assert(bignum.isbignum(x), string.format("invalid type: %s != %s", type(x), t))
    assert(x >= bignum.number(0), string.format("%s must be positive number", bignum.tostring(x)))
  elseif (x and t == 'uint') then
    -- check unsigned integer
    assert(type(x) == 'number', string.format("expected 'number' but got '%s'", type(x)))
    assert(math.floor(x) == x, "the number must be an integer")
    assert(x >= 0, "the number must be 0 or positive")
  else
    -- check default lua types
    assert(type(x) == t, string.format("expected '%s' but got '%s'", t, type(x)))
  end
end

function set_owner(new_owner)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the new owner is a valid address
  _typecheck(new_owner, 'address')

  -- set the new owner
  _owner:set(new_owner)
end

function pause()
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- mark as paused
  _paused:set(true)
end

function unpause()
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- mark as not paused
  _paused:set(false)
end

function create_associated_token(name, symbol, decimals)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the token is not set
  assert(_token:get() == nil, "token is already created")

  -- create the token using the token factory
  local token = contract.call(arc1_factory, "new_token", name, symbol, decimals,
                             '0', {mintable=true, burnable=true, all_approval=true})

  -- save the token address
  _token:set(token)

  -- return the token address
  return token
end

function get_token()
  return _token:get()
end

--------------------------------------------------------------------------------

-- transfer tokens from other chain to this chain
-- tokens are locked on the other chain and minted on this chain
function swapin_mint(token, amount, recipient)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- check that the supplied token is the same as the bridge token
  assert(token == _token:get(), "invalid token")

  -- check that the recipient is a valid address
  _typecheck(recipient, 'address')

  -- mint the tokens to the recipient
  contract.call(token, "mint", amount, recipient)

  -- emit the swapin event
  contract.event("swapin_mint", token, amount, recipient)
end

-- transfer tokens from other chain to this chain
-- tokens are burned on the other chain and unlocked on this chain
function swapin_transfer(token, amount, recipient)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- check that the supplied token is the same as the bridge token
  assert(token == _token:get(), "invalid token")

  -- check that the recipient is a valid address
  _typecheck(recipient, 'address')

  -- transfer the tokens to the recipient
  contract.call(token, "transfer", amount, recipient)

  -- emit the swapin event
  contract.event("swapin_transfer", token, amount, recipient)
end

--------------------------------------------------------------------------------

-- transfer tokens from this chain to other chain
-- tokens are burned on this chain and unlocked on the other chain
function swapout_burn(token, amount, recipient)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- check that the supplied token is the same as the bridge token
  assert(token == _token:get(), "invalid token")

  -- check that the recipient is a valid address
  _typecheck(recipient, 'address')

  -- burn the tokens from the bridge
  contract.call(token, "burn", amount)

  -- emit the swapout event
  contract.event("swapout_burn", token, amount, recipient)
end

-- transfer tokens from this chain to other chain
-- tokens are locked on this chain and minted on the other chain
--> this function is a no-op! no need to be called <--
function swapout_transfer(token, amount, recipient)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- check that the supplied token is the same as the bridge token
  assert(token == _token:get(), "invalid token")

  -- check that the recipient is a valid address
  _typecheck(recipient, 'address')

  -- emit the swapout event
  contract.event("swapout_transfer", token, amount, recipient)
end

-- called when ARC1 tokens are transferred to this contract.
-- anyone can transfer tokens to this contract.
-- only the bridge token is accepted.
-- currently there is no minimum or maximum amount of tokens that can be transferred.
function tokensReceived(operator, from, amount, to_chain, to_address)
  _typecheck(from, 'address')
  _typecheck(amount, 'ubig')

  -- the contract calling this function
  local token = system.getSender()

  -- check that the token is the same as the bridge token
  assert(token == _token:get(), "invalid token")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- emit the tokens_received event
  contract.event("tokens_received", token, from, amount, to_chain, to_address)
end

-- register the exported functions
abi.register(set_owner, pause, unpause, create_associated_token, tokensReceived,
             swapin_mint, swapin_transfer, swapout_burn, swapout_transfer)
abi.register_view(get_token)
