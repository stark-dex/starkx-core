%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from src.utils.handle_revoked_refs import handle_revoked_refs

@contract_interface
namespace IStorageContract {
    // Get account balance for user
    func get_account_balance(user : felt, asset : felt) -> (amount : felt) {
    }
    // Set account balance for user
    func set_account_balance(user : felt, asset : felt, new_amount : felt) {
    }
    // Get order balance for user
    func get_order_balance(user : felt, asset : felt) -> (amount : felt) {
    }
    // Set order balance for user
    func set_order_balance(user : felt, asset : felt, new_amount : felt) {
    }
}

//
// Storage vars
// 

// Stores orders in doubly linked lists.
@storage_var
func l2_storage_contract_address() -> (addr : felt) {
}

namespace Balances {

    //
    // Functions
    //

    // Initialiser function
    // @dev Called by GatewayContract on deployment
    func initialise{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        _l2_storage_contract_address
    ) {
        l2_storage_contract_address.write(_l2_storage_contract_address);
        return ();
    }

    // Getter for user balances
    // @param user : User EOA
    // @param asset : felt representation of ERC20 token contract address
    // @param in_account : 1 for account balances, 0 for order balances
    // @return amount : token balance
    func get_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        user : felt, asset : felt, in_account : felt
    ) -> (amount : felt) {
        let (storage_addr) = l2_storage_contract_address.read();
        if (in_account == 1) {
            let (amount) = IStorageContract.get_account_balance(storage_addr, user, asset);
            return (amount=amount);
        } else {
            let (amount) = IStorageContract.get_order_balance(storage_addr, user, asset);
            return (amount=amount);
        }
    }

    // Setter for user balances
    // @param user : User EOA
    // @param asset : felt representation of ERC20 token contract address
    // @param in_account : 1 for account balances, 0 for order balances
    // @param amount : new token balance
    func set_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        user : felt, asset : felt, in_account : felt, new_amount : felt
    ) {
        let (storage_addr) = l2_storage_contract_address.read();
        if (in_account == 1) {
            IStorageContract.set_account_balance(storage_addr, user, asset, new_amount);
            return ();
        } else {
            IStorageContract.set_order_balance(storage_addr, user, asset, new_amount);
            return ();
        }
    }

    // Transfer balance from one user to another. 
    // @param sender : sender EOA
    // @param recipient : recipient EOA
    // @param asset : felt representation of ERC20 token contract address
    // @param amount : token balance
    // @return success : 1 if successful, 0 otherwise
    func transfer_balance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        sender : felt, recipient : felt, asset : felt, amount : felt
    ) -> (success : felt) {
        alloc_locals;
        let (sender_balance) = get_balance(sender, asset, 1);
        let is_sufficient = is_le(amount, sender_balance);
        let is_positive = is_le(1, amount);
        with_attr error_message("[Balances] transfer_balance > Balance must be sufficient and positive, sender balance is {sender_balance} but requested transfer of {amount}") {
            assert is_sufficient + is_positive = 2;
        }
        let (recipient_balance) = get_balance(recipient, asset, 1);
        set_balance(sender, asset, 1, sender_balance - amount);
        set_balance(recipient, asset, 1, recipient_balance + amount);
        return (success=1);
    }

    // Transfer account balance to order balance.
    // @param user : User EOA
    // @param asset : felt representation of ERC20 token contract address
    // @param amount : balance to transfer to open order
    // @return success : 1 if successful, 0 otherwise
    func transfer_to_order{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        user : felt, asset : felt, amount : felt
    ) -> (success : felt) {
        alloc_locals;
        let (balance) = get_balance(user, asset, 1);
        let is_sufficient = is_le(amount, balance);
        let is_positive = is_le(1, amount);
        if (is_sufficient + is_positive == 2) {
            let (locked_balance) = get_balance(user, asset, 0);
            set_balance(user, asset, 1, balance - amount);
            set_balance(user, asset, 0, locked_balance + amount);
            let (user_account_balance) = get_balance(user, asset, 1);
            let (user_locked_balance) = get_balance(user, asset, 0);        
            return (success=1);
        } else {
            return (success=0);
        }   
    }

    // Transfer order balance to account balance.
    // @param user : User EOA
    // @param asset : felt representation of ERC20 token contract address
    // @param amount : balance to transfer from open order to account balance
    // @return success : 1 if successful, 0 otherwise
    func transfer_from_order{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
        user : felt, asset : felt, amount : felt
    ) -> (success : felt) {
        alloc_locals;
        let (locked_balance) = get_balance(user, asset, 0);
        let is_sufficient = is_le(amount, locked_balance);
        let is_positive = is_le(1, amount);
        if (is_sufficient + is_positive == 2) {
            let (balance) = get_balance(user, asset, 1);
            set_balance(user, asset, 0, locked_balance - amount);
            set_balance(user, asset, 1, balance + amount);
            let (user_account_balance) = get_balance(user, asset, 1);
            let (user_locked_balance) = get_balance(user, asset, 0);
            return (success=1);
        } else {
            return (success=0);
        }   
    }
}