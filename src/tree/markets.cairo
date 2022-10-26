%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from starkware.starknet.common.syscalls import get_block_timestamp
from src.tree.limits import Limit, limits, print_limit, print_dfs_in_order
from src.tree.orders import Order, print_list, print_order
from starkware.cairo.common.alloc import alloc

struct Market {
    id : felt,
    bid_tree_id : felt,
    ask_tree_id : felt,
    lowest_ask : felt,
    highest_bid : felt,
    base_asset : felt,
    quote_asset : felt,
    controller : felt,
}

@contract_interface
namespace IOrdersContract {
    // Getter for head ID and tail ID.
    func get_head_and_tail(limit_id : felt) -> (head_id : felt, tail_id : felt) {
    }
    // Getter for list length.
    func get_length(limit_id : felt) -> (len : felt) {
    }
    // Getter for particular order.
    func get_order(id : felt) -> (order : Order) {
    }
    // Insert new order to the list.
    func push(is_buy : felt, price : felt, amount : felt, dt : felt, owner : felt, limit_id : felt) -> (new_order : Order) {
    }
    // Remove order from head of list
    func shift(limit_id : felt) -> (del : Order) {
    } 
    // Retrieve order at particular position in the list.
    func get(limit_id : felt, idx : felt) -> (order : Order) {
    }
    // Update order at particular position in the list.
    func set(id : felt, is_buy : felt, price : felt, amount : felt, filled : felt, dt : felt, owner : felt) -> 
        (success : felt) {
    }
    // Update filled amount of order.
    func set_filled(id : felt, filled : felt) -> (success : felt) {  
    }
    // Remove value at particular position in the list.
    func remove(limit_id : felt, idx : felt) -> (del : Order) {
    }
}

@contract_interface
namespace ILimitsContract {
    // Getter for limit price
    func get_limit(limit_id : felt) -> (limit : Limit) {
    }
    // Getter for lowest limit price within tree
    func get_min(tree_id : felt) -> (min : Limit) {
    }
    // Getter for highest limit price within tree
    func get_max(tree_id : felt) -> (max : Limit) {
    }
    // Insert new limit price into BST.
    func insert(price : felt, tree_id : felt, market_id : felt) -> (new_limit : Limit) {
    }
    // Find a limit price in binary search tree.
    func find(price : felt, tree_id : felt) -> (limit : Limit, parent : Limit) {    
    }
    // Deletes limit price from BST
    func delete(price : felt, tree_id : felt, market_id : felt) -> (del : Limit) {
    }
    // Setter function to update details of a limit price.
    func update(limit_id : felt, total_vol : felt, order_len : felt, order_head : felt, order_tail : felt ) -> (success : felt) {
    }   
}

@contract_interface
namespace IBalancesContract {
    // Getter for user balances
    func get_balance(user : felt, asset : felt, in_account : felt) -> (amount : felt) {
    }
    // Setter for user balances
    func set_balance(user : felt, asset : felt, in_account : felt, new_amount : felt) {
    }
    // Transfer balance from one user to another.
    func transfer_balance(sender : felt, recipient : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Transfer account balance to order balance.
    func transfer_to_order(user : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Transfer order balance to account balance.
    func transfer_from_order(user : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Fill an open bid order.
    func fill_bid_order(buyer : felt, seller : felt, base_asset : felt, quote_asset : felt, amount : felt, price : felt) -> (success : felt) {
    }
    // Fill an open ask order.
    func fill_ask_order(buyer : felt, seller : felt, base_asset : felt, quote_asset : felt, amount : felt, price : felt) -> (success : felt) {
    }
}

// Stores active markets.
@storage_var
func markets(id : felt) -> (market : Market) {
}

// Stores on-chain mapping of asset addresses to market id.
@storage_var
func market_ids(base_asset : felt, quote_asset : felt) -> (market_id : felt) {
}

// Stores pointers to bid and ask limit trees.
@storage_var
func trees(id : felt) -> (root_id : felt) {
}

// Stores latest market id.
@storage_var
func curr_market_id() -> (id : felt) {
}

// Stores latest tree id.
@storage_var
func curr_tree_id() -> (id : felt) {
}

// Emit create market event.
@event
func log_create_market(id : felt, bid_tree_id : felt, ask_tree_id : felt, lowest_ask : felt, highest_bid : felt, base_asset : felt, quote_asset : felt, controller : felt) {
}

// Emit create new bid.
@event
func log_create_bid(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt) {
}

// Emit create new ask.
@event
func log_create_ask(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt) {
}

// Emit bid taken by buy order.
@event
func log_bid_taken(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, seller : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

// Emit offer taken by buy order.
@event
func log_offer_taken(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, buyer : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

// Emit buy order filled.
@event
func log_buy_filled(id : felt, limit_id : felt, market_id : felt, dt : felt, buyer : felt, seller : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

// Emit sell order filled.
@event
func log_sell_filled(id : felt, limit_id : felt, market_id : felt, dt : felt, seller : felt, buyer : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} () {
    curr_market_id.write(1);
    curr_tree_id.write(1);
    return ();
}

// Create a new market for exchanging between two assets.
// @param base_asset : felt representation of ERC20 base asset contract address
// @param quote_asset : felt representation of ERC20 quote asset contract address
// @param controller : felt representation of account that controls the market
func create_market{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    base_asset : felt, quote_asset : felt) -> (new_market : Market
) {
    alloc_locals;
    
    let (market_id) = curr_market_id.read();
    let (tree_id) = curr_tree_id.read();
    let (caller) = get_caller_address();
    
    tempvar new_market: Market* = new Market(
        id=market_id, bid_tree_id=tree_id, ask_tree_id=tree_id+1, lowest_ask=0, highest_bid=0, 
        base_asset=base_asset, quote_asset=quote_asset, controller=caller
    );
    markets.write(market_id, [new_market]);

    curr_market_id.write(market_id + 1);
    curr_tree_id.write(tree_id + 2);
    market_ids.write(base_asset, quote_asset, market_id + 1);

    log_create_market.emit(
        id=market_id, bid_tree_id=tree_id, ask_tree_id=tree_id+1, lowest_ask=0, highest_bid=0, 
        base_asset=base_asset, quote_asset=quote_asset, controller=caller
    );

    return (new_market=[new_market]);
}

// Update inside quote of market.
func update_inside_quote{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    market_id : felt, lowest_ask : felt, highest_bid : felt) -> (success : felt
) {
    let (market) = markets.read(market_id);
    if (market.id == 0) {
        return (success=0);
    }
    tempvar new_market: Market* = new Market(
        id=market_id, bid_tree_id=market.bid_tree_id, ask_tree_id=market.ask_tree_id, lowest_ask=lowest_ask, 
        highest_bid=highest_bid, base_asset=market.base_asset, quote_asset=market.quote_asset, controller=market.controller
    );
    markets.write(market_id, [new_market]);
    return (success=1);
}

// Submit a new bid (limit buy order) to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @param post_only : 1 if create bid in post only mode, 0 otherwise
// @return success : 1 if successfully created bid, 0 otherwise
func create_bid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, price : felt, amount : felt, post_only : felt
) -> (success : felt) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let (limit, _) = ILimitsContract.find(limits_addr, price, market.bid_tree_id);
    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);

    if (market.id == 0) {
        with_attr error_message("Market does not exist") {
            assert 0 = 1;
        }
        return (success=0);
    }

    // If ask exists and price greater than lowest ask, place market buy
    if (lowest_ask.id == 0) {
        handle_revoked_refs();
    } else {        
        let is_market_order = is_le(lowest_ask.price, price);
        handle_revoked_refs();
        if (is_market_order == 1) {
            if (post_only == 0) {
                let (buy_order_success) = buy(orders_addr, limits_addr, balances_addr, market.id, price, amount);
                assert buy_order_success = 1;
                handle_revoked_refs();
                return (success=1);
            } else {
                handle_revoked_refs();
                return (success=0);
            }
            
        } else {
            handle_revoked_refs();
        }
    }
    
    // Otherwise, place limit order
    if (limit.id == 0) {
        // Limit tree doesn't exist yet, insert new limit tree
        let (new_limit) = ILimitsContract.insert(limits_addr, price, market.bid_tree_id, market.id);
        let create_limit_success = is_le(1, new_limit.id);
        assert create_limit_success = 1;
        let (create_bid_success) = create_bid_helper(orders_addr, limits_addr, balances_addr, market, new_limit, price, amount);
        assert create_bid_success = 1;
        handle_revoked_refs();
    } else {
        // Add order to limit tree
        let (create_bid_success) = create_bid_helper(orders_addr, limits_addr, balances_addr, market, limit, price, amount);
        assert create_bid_success = 1;
        handle_revoked_refs();
    }
    
    return (success=1);
}

// Helper function for creating a new bid (limit buy order).
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market : market to which bid is being submitted
// @param limit : limit tree to which bid is being submitted
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func create_bid_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market : Market, limit : Limit, 
    price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.base_asset, 1);
    let balance_sufficient = is_le(amount, account_balance);
    %{ print("[markets.cairo] create_bid_helper > amount: {}, account_balance: {}".format(ids.amount, ids.account_balance)) %}
    if (balance_sufficient == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let (dt) = get_block_timestamp();
    let (new_order) = IOrdersContract.push(orders_addr, 1, price, amount, dt, caller, limit.id);
    let (new_head, new_tail) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
    let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol + amount, limit.order_len + 1, new_head, new_tail);
    assert update_limit_success = 1;

    let (highest_bid) = IOrdersContract.get_order(orders_addr, market.highest_bid);
    let highest_bid_exists = is_le(1, highest_bid.id); 
    let is_not_highest_bid = is_le(price, highest_bid.price);
    if (is_not_highest_bid + highest_bid_exists == 2) {
        handle_revoked_refs();
    } else {
        let (update_market_success) = update_inside_quote(market.id, market.lowest_ask, new_order.id);
        assert update_market_success = 1;
        handle_revoked_refs();
    }
    let (update_balance_success) = IBalancesContract.transfer_to_order(balances_addr, caller, market.base_asset, amount);
    assert update_balance_success = 1;

    log_create_bid.emit(id=new_order.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=price, amount=amount);

    return (success=1);
}

// Submit a new ask (limit sell order) to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @param post_only : 1 if create bid in post only mode, 0 otherwise
// @return success : 1 if successfully created ask, 0 otherwise
func create_ask{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, price : felt, amount : felt, post_only : felt
) -> (success : felt) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let (limit, _) = ILimitsContract.find(limits_addr, price, market.ask_tree_id);
    let (highest_bid) = IOrdersContract.get_order(orders_addr, market.highest_bid);

    if (market.id == 0) {
        with_attr error_message("Market does not exist") {
            assert 0 = 1;
        }
        return (success=0);
    }

    // If bid exists and price lower than highest bid, place market sell
    if (highest_bid.id == 1) {
        let is_market_order = is_le(price, highest_bid.price);
        handle_revoked_refs();
        if (is_market_order == 1) {
            if (post_only == 0) {
                let (sell_order_success) = sell(orders_addr, limits_addr, balances_addr, market.id, price, amount);
                assert sell_order_success = 1;
                handle_revoked_refs();
                return (success=1);
            } else {
                handle_revoked_refs();
                return (success=0);
            }
        } else {
            handle_revoked_refs();
        }
    } else {
        handle_revoked_refs();
    }

    // Otherwise, place limit sell order
    if (limit.id == 0) {
        // Limit tree doesn't exist yet, insert new limit tree
        let (new_limit) = ILimitsContract.insert(limits_addr, price, market.ask_tree_id, market.id);
        let create_limit_success = is_le(1, new_limit.id);
        assert create_limit_success = 1;
        let (create_ask_success) = create_ask_helper(orders_addr, limits_addr, balances_addr, market, new_limit, price, amount);
        assert create_ask_success = 1;
        handle_revoked_refs();
    } else {
        // Add order to limit tree
        let (create_ask_success) = create_ask_helper(orders_addr, limits_addr, balances_addr, market, limit, price, amount);
        assert create_ask_success = 1;
        handle_revoked_refs();
    }
    
    return (success=1);
}

// Helper function for creating a new ask (limit sell order).
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market : market to which bid is being submitted
// @param limit : limit tree to which bid is being submitted
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func create_ask_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market : Market, limit : Limit, 
    price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.quote_asset, 1);
    let balance_sufficient = is_le(amount, account_balance);
    if (balance_sufficient == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let (dt) = get_block_timestamp();
    let (new_order) = IOrdersContract.push(orders_addr, 0, price, amount, dt, caller, limit.id);
    let (new_head, new_tail) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
    let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol + amount, limit.order_len + 1, new_head, new_tail);
    assert update_limit_success = 1;

    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);
    let lowest_ask_exists = is_le(1, lowest_ask.id); 
    let is_not_lowest_ask = is_le(lowest_ask.price, price);
    if (lowest_ask_exists + is_not_lowest_ask == 2) {
        handle_revoked_refs();        
    } else {
        let (update_market_success) = update_inside_quote(market.id, new_order.id, market.highest_bid);
        assert update_market_success = 1;
        handle_revoked_refs();
    }
    let (update_balance_success) = IBalancesContract.transfer_to_order(balances_addr, caller, market.quote_asset, amount);
    assert update_balance_success = 1;

    log_create_ask.emit(id=new_order.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=price, amount=amount);

    return (success=1);
}

// Submit a new market buy order to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param max_price : highest price at which buyer is willing to fulfill order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func buy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, max_price : felt, 
    amount : felt
        ) -> (
    success : felt
) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let lowest_ask_exists = is_le(1, market.lowest_ask);
    %{ print("[markets.cairo] buy > amount: {}".format(ids.amount)) %}
    %{ print("[markets.cairo] buy > lowest_ask_exists: {}".format(ids.lowest_ask_exists)) %}
    if (lowest_ask_exists == 0) {
        let (create_bid_success) = create_bid(orders_addr, limits_addr, balances_addr, market_id, max_price, amount, 0);
        assert create_bid_success = 1;
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }
    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);
    let (base_amount, _) = unsigned_div_rem(amount, lowest_ask.price);
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.base_asset, 1);
    let is_sufficient = is_le(base_amount, account_balance);
    let is_positive = is_le(1, amount);
    %{ print("[markets.cairo] buy > is_sufficient: {}, is_positive: {}, market.id: {}".format(ids.is_sufficient, ids.is_positive, ids.market.id)) %}
    if (is_sufficient * is_positive * market.id == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let is_below_max_price = is_le(lowest_ask.price, max_price);
    %{ print("[markets.cairo] buy > is_below_max_price: {}".format(ids.is_below_max_price)) %}
    if (is_below_max_price == 0) {
        let (create_bid_success) = create_bid(orders_addr, limits_addr, balances_addr, market_id, max_price, amount, 0);
        assert create_bid_success = 1;
        handle_revoked_refs();
        return (success=1);
    } else {
        handle_revoked_refs();
    }
    
    let (dt) = get_block_timestamp();
    %{ print("[markets.cairo] buy > dt: {}".format(ids.dt))%}
    %{ print("[markets.cairo] buy > amount: {}".format(ids.amount))%}
    let is_partial_fill = is_le(amount, lowest_ask.amount - lowest_ask.filled - 1);
    %{ print("[markets.cairo] buy > is_partial_fill: {}".format(ids.is_partial_fill)) %}
    let (limit) = ILimitsContract.get_limit(limits_addr, lowest_ask.limit_id);
    if (is_partial_fill == 1) {
        // Partial fill of order
        IOrdersContract.set_filled(orders_addr, lowest_ask.id, amount);
        let (update_balances_success) = IBalancesContract.fill_ask_order(balances_addr, caller, lowest_ask.owner, market.base_asset, market.quote_asset, amount, lowest_ask.price);
        assert update_balances_success = 1;
        let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol - amount, limit.order_len, limit.order_head, limit.order_tail);                
        assert update_limit_success = 1;
        log_offer_taken.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=lowest_ask.owner, buyer=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=amount, total_filled=amount);
        log_buy_filled.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, buyer=caller, seller=lowest_ask.owner, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=amount, total_filled=amount);
        handle_revoked_refs();
        return (success=1);
    } else {
        // Fill entire order
        IOrdersContract.set_filled(orders_addr, lowest_ask.id, lowest_ask.amount);
        IOrdersContract.shift(orders_addr, lowest_ask.limit_id);
        let (new_head_id, new_tail_id) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
        %{ print("[markets.cairo] buy > ILimitsContract.update({}, {}, {}, {}, {})".format(ids.limit.id, ids.limit.total_vol - ids.lowest_ask.amount + ids.lowest_ask.filled, ids.limit.order_len - 1, ids.new_head_id, ids.new_tail_id)) %}
        let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol - lowest_ask.amount + lowest_ask.filled, limit.order_len - 1, new_head_id, new_tail_id);                
        assert update_limit_success = 1;

        %{ print("[markets.cairo] buy > new_head_id: {}".format(ids.new_head_id)) %}
        if (new_head_id == 0) {
            ILimitsContract.delete(limits_addr, lowest_ask.price, market.ask_tree_id, market.id);
            let (next_limit) = ILimitsContract.get_min(limits_addr, market.ask_tree_id);
            %{ print("[markets.cairo] buy > next_limit.id: {}".format(ids.next_limit.id)) %}
            if (next_limit.id == 0) {
                let (update_market_success) = update_inside_quote(market.id, 0, market.highest_bid);
                assert update_market_success = 1;
                handle_revoked_refs();
            } else {
                let (next_head, _) = IOrdersContract.get_head_and_tail(orders_addr, next_limit.id);
                let (update_market_success) = update_inside_quote(market.id, next_head, market.highest_bid);
                assert update_market_success = 1;
                handle_revoked_refs();
            }
            handle_revoked_refs();
        } else {
            let (update_market_success) = update_inside_quote(market.id, new_head_id, market.highest_bid);
            assert update_market_success = 1;
            handle_revoked_refs();
        }
        let (update_account_balance_success) = IBalancesContract.fill_ask_order(balances_addr, caller, lowest_ask.owner, market.base_asset, market.quote_asset, lowest_ask.amount - lowest_ask.filled, lowest_ask.price);
        assert update_account_balance_success = 1;

        log_offer_taken.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=lowest_ask.owner, buyer=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=lowest_ask.amount - lowest_ask.filled, total_filled=amount);
        log_buy_filled.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, buyer=caller, seller=lowest_ask.owner, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=lowest_ask.amount - lowest_ask.filled, total_filled=amount);

        buy(orders_addr, limits_addr, balances_addr, market_id, max_price, amount - lowest_ask.amount + lowest_ask.filled); 
        
        handle_revoked_refs();
        return (success=1);
    }
}

// Submit a new market sell order to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param min_price : lowest price at which seller is willing to fulfill order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created ask, 0 otherwise
func sell{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, min_price : felt, 
    amount : felt
        ) -> (
    success : felt
) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let highest_bid_exists = is_le(1, market.highest_bid);
    %{ print("[markets.cairo] sell > amount: {}".format(ids.amount)) %}
    %{ print("[markets.cairo] sell > highest_bid: {}".format(ids.highest_bid_exists)) %}
    if (highest_bid_exists == 0) {
        let (create_ask_success) = create_ask(orders_addr, limits_addr, balances_addr, market_id, min_price, amount, 0);
        assert create_ask_success = 1;
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }
    let (highest_bid) = IOrdersContract.get_order(orders_addr, market.highest_bid);
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.quote_asset, 1);
    let is_sufficient = is_le(amount, account_balance);
    let is_positive = is_le(1, amount);
    %{ print("[markets.cairo] sell > is_sufficient: {}, is_positive: {}, market.id: {}".format(ids.is_sufficient, ids.is_positive, ids.market.id)) %}
    if (is_sufficient * is_positive * market.id == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let is_above_min_price = is_le(min_price, highest_bid.price);
    %{ print("[markets.cairo] sell > is_above_min_price: {}".format(ids.is_above_min_price)) %}
    if (is_above_min_price == 0) {
        let (create_ask_success) = create_ask(orders_addr, limits_addr, balances_addr, market_id, min_price, amount, 0);
        assert create_ask_success = 1;
        handle_revoked_refs();
        return (success=1);
    } else {
        handle_revoked_refs();
    }
    
    let (dt) = get_block_timestamp();
    %{ print("[markets.cairo] sell > dt: {}".format(ids.dt))%}
    %{ print("[markets.cairo] sell > amount: {}".format(ids.amount))%}
    let is_partial_fill = is_le(amount, highest_bid.amount - highest_bid.filled - 1);
    %{ print("[markets.cairo] sell > is_partial_fill: {}".format(ids.is_partial_fill)) %}
    let (limit) = ILimitsContract.get_limit(limits_addr, highest_bid.limit_id);
    if (is_partial_fill == 1) {
        // Partial fill of order
        IOrdersContract.set_filled(orders_addr, highest_bid.id, amount);
        let (update_balances_success) = IBalancesContract.fill_bid_order(balances_addr, highest_bid.owner, caller, market.base_asset, market.quote_asset, amount, highest_bid.price);
        assert update_balances_success = 1;
        let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol - amount, limit.order_len, limit.order_head, limit.order_tail);                
        assert update_limit_success = 1;
        log_bid_taken.emit(id=highest_bid.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=highest_bid.owner, seller=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=highest_bid.price, amount=amount, total_filled=amount);
        log_sell_filled.emit(id=highest_bid.id, limit_id=limit.id, market_id=market.id, dt=dt, seller=caller, buyer=highest_bid.owner, base_asset=market.base_asset, quote_asset=market.quote_asset, price=highest_bid.price, amount=amount, total_filled=amount);
        handle_revoked_refs();
        return (success=1);
    } else {
        // Fill entire order
        IOrdersContract.set_filled(orders_addr, highest_bid.id, highest_bid.amount);
        IOrdersContract.shift(orders_addr, highest_bid.limit_id);
        let (new_head_id, new_tail_id) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
        %{ print("[markets.cairo] sell > ILimitsContract.update({}, {}, {}, {}, {})".format(ids.limit.id, ids.limit.total_vol - ids.lowest_ask.amount + ids.lowest_ask.filled, ids.limit.order_len - 1, ids.new_head_id, ids.new_tail_id)) %}
        let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol - highest_bid.amount + highest_bid.filled, limit.order_len - 1, new_head_id, new_tail_id);                
        assert update_limit_success = 1;

        %{ print("[markets.cairo] sell > new_head_id: {}".format(ids.new_head_id)) %}
        if (new_head_id == 0) {
            ILimitsContract.delete(limits_addr, highest_bid.price, market.bid_tree_id, market.id);
            let (next_limit) = ILimitsContract.get_max(limits_addr, market.bid_tree_id);
            %{ print("[markets.cairo] sell > next_limit.id: {}".format(ids.next_limit.id)) %}
            if (next_limit.id == 0) {
                let (update_market_success) = update_inside_quote(market.id, market.lowest_ask, 0);
                assert update_market_success = 1;
                handle_revoked_refs();
            } else {
                let (next_head, _) = IOrdersContract.get_head_and_tail(orders_addr, next_limit.id);
                let (update_market_success) = update_inside_quote(market.id, market.lowest_ask, next_head);
                assert update_market_success = 1;
                handle_revoked_refs();
            }
            handle_revoked_refs();
        } else {
            let (update_market_success) = update_inside_quote(market.id, market.lowest_ask, new_head_id);
            assert update_market_success = 1;
            handle_revoked_refs();
        }
        let (update_account_balance_success) = IBalancesContract.fill_bid_order(balances_addr, caller, highest_bid.owner, market.base_asset, market.quote_asset, highest_bid.amount - highest_bid.filled, highest_bid.price);
        assert update_account_balance_success = 1;

        log_bid_taken.emit(id=highest_bid.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=highest_bid.owner, seller=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=highest_bid.price, amount=highest_bid.amount-highest_bid.filled, total_filled=amount);
        log_sell_filled.emit(id=highest_bid.id, limit_id=limit.id, market_id=market.id, dt=dt, seller=caller, buyer=highest_bid.owner, base_asset=market.base_asset, quote_asset=market.quote_asset, price=highest_bid.price, amount=highest_bid.amount-highest_bid.filled, total_filled=amount);

        sell(orders_addr, limits_addr, balances_addr, market_id, min_price, amount - highest_bid.amount + highest_bid.filled); 
        
        handle_revoked_refs();
        return (success=1);
    }
}

// Cancel an order
func cancel() {
    
}

func print_market{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (market : Market) {
    %{ 
        print("id: {}, bid_tree_id: {}, ask_tree_id: {}, lowest_ask: {}, highest_bid: {}, base_asset: {}, quote_asset: {}, controller: {}".format(ids.market.id, ids.market.bid_tree_id, ids.market.ask_tree_id, ids.market.lowest_ask, ids.market.highest_bid, ids.market.base_asset, ids.market.quote_asset, ids.market.controller)) 
    %}
    return ();
}

// Utility function to handle revoked implicit references.
// @dev tempvars used to handle revoked implict references
func handle_revoked_refs{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} () {
    tempvar syscall_ptr=syscall_ptr;
    tempvar pedersen_ptr=pedersen_ptr;
    tempvar range_check_ptr=range_check_ptr;
    return ();
}