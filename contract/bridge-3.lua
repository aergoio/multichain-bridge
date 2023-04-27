--[[
  MultiChain Bridge Contract
  This version of the bridge contract can receive tokens from the user
]]

-- state variables
state.var {
  _owner = state.value(),     -- address
  _paused = state.value(),    -- bool
  _tokens = state.map(),      -- address -> string
  _last_swapout_id = state.value(), -- uint
  _swapouts = state.map(),    -- uint -> {address, uint}
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
    assert(#x == 52, string.format("invalid address length: %s (%s)", x, #x))
    -- check character
    local invalidChar = string.match(x, '[^123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]')
    assert(invalidChar == nil, string.format("invalid address format: %s contains invalid char %s", x, invalidChar or 'nil'))
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

  -- create the token using the token factory
  local token = contract.call(arc1_factory, "new_token", name, symbol, decimals,
                             '0', {mintable=true, burnable=true})

  -- save the token address
  _tokens[token] = "other_chain"

  -- return the token address
  return token
end

function add_source_token(token)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the supplied token is a valid address
  _typecheck(token, 'address')

  -- check that the token is not already set
  assert(_tokens[token] == nil, "token is already added")

  -- save the token address
  _tokens[token] = "this_chain"
end

function get_token_info(token)
  _typecheck(token, 'address')
  return _tokens[token]
end

--------------------------------------------------------------------------------

-- transfer tokens from other chain to this chain
-- tokens are locked on the other chain and minted on this chain
function swapin_mint(token, amount, recipient)
  -- check the function caller
  assert(system.getSender() == _owner:get(), "only the bridge owner can call this function")

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- check that the token is supported by this bridge
  assert(_tokens[token] == "other_chain", "invalid token")

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

  -- check that the token is supported by this bridge
  assert(_tokens[token] == "this_chain", "invalid token")

  -- check that the recipient is a valid address
  _typecheck(recipient, 'address')

  -- transfer the tokens to the recipient
  contract.call(token, "transfer", amount, recipient)

  -- emit the swapin event
  contract.event("swapin_transfer", token, amount, recipient)
end

--------------------------------------------------------------------------------

-- retrieve the id of the last swapout
function get_last_swapout_id()
  return _last_swapout_id:get()
end

-- retrieve details of a given swapout
function get_swapout_info(swapout_id)
  local swapout = _swapouts[tostring(swapout_id)]
  assert(swapout ~= nil, "invalid swapout id")
  return swapout
end

-- register a swapout request
-- used to transfer tokens from this chain to another chain
local function swapout(type, token, amount, from, to_chain, to_address)

  -- generate a unique swapout id
  local swapout_id = _last_swapout_id:get() or 0
  swapout_id = swapout_id + 1
  _last_swapout_id:set(swapout_id)

  -- save the swapout request
  _swapouts[tostring(swapout_id)] = {
    token = token,
    amount = amount,
    from = from,
    to_chain = to_chain,
    to_address = to_address,
  }

  if type == "burn" then
    -- tokens are burned on this chain and unlocked on the other chain
    -- burn the tokens from the bridge
    contract.call(token, "burn", amount)
  elseif type == "transfer" then
    -- tokens are locked on this chain and minted on the other chain
    -- keep the transferred tokens on the bridge contract
  else
    -- invalid swapout type
    assert(false, "invalid swapout type")
  end

  -- emit the swapout event
  contract.event("swapout", type, swapout_id, token, amount, from, to_chain, to_address)
end

-- called when ARC1 tokens are transferred to this contract.
-- anyone can transfer tokens to this contract.
-- only tokens that are supported by this bridge can be transferred.
-- currently there is no minimum or maximum amount of tokens that can be transferred.
function tokensReceived(operator, from, amount, to_chain, to_address)
  _typecheck(from, 'address')
  _typecheck(amount, 'ubig')

  -- check that the contract is not paused
  assert(not _paused:get(), "contract is paused")

  -- the contract calling this function
  local token = system.getSender()

  local token_source = _tokens[token]
  if token_source == "this_chain" then
    -- call the swapout_transfer function
    swapout("transfer", token, amount, from, to_chain, to_address)

  elseif token_source == "other_chain" then
    -- call the swapout_burn function
    swapout("burn", token, amount, from, to_chain, to_address)

  else
    error("token not supported")
  end

end

-- register the exported functions
abi.register(set_owner, pause, unpause, create_associated_token, add_source_token,
             swapin_mint, swapin_transfer, tokensReceived)
abi.register_view(get_token_info, get_last_swapout_id, get_swapout_info)
