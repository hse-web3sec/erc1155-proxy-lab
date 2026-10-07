# ERC-1155 Proxy Lab

An educational Solidity project built with Foundry and OpenZeppelin. It demonstrates minting and burning ERC-1155 tokens through a proxy and compares a proxy without an upgrade mechanism with an upgradeable Transparent Proxy.

## Examples

| File                                    | Purpose                                                                                                                                          |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `src/MyToken.sol`                       | ERC-1155 token: owner-only `mint`, `mintBatch`, and `setURI`; `burn` and `burnBatch` callable by the holder or an approved operator              |
| `test/MyToken.t.sol`                    | An `ERC1967Proxy` without an upgrade mechanism; tests for minting, burning, batch minting, ownership, initialization, and rejected upgrade calls |
| `src/ERC1155v2.sol`                     | An educational V2 with `version() == 2` and an intentionally reverting `mint`                                                                    |
| `test/ERC1155.t.sol`                    | Transparent Proxy deployment and upgrade to V2 using OpenZeppelin Foundry Upgrades                                                               |
| `src/Counter.sol`, `test/Counter.t.sol` | A basic Foundry counter example with a fuzz test                                                                                                 |
| `script/Counter.s.sol` | Counter deployment, increment, and read-only entry points for Anvil and historical forks |

Both proxy examples use `MyToken`. The `virtual` modifier on `mint` allows V2 to override it through inheritance; it does not make a deployed contract upgradeable by itself.

## Setup

Run these commands in Bash on Linux, macOS, or WSL. If your terminal uses another shell, start `bash` first. Install Git, [Foundry](https://getfoundry.sh/) (with `forge`, `cast`, and `anvil` in `PATH`), and Node.js 20+ with npm for OpenZeppelin upgrade validation.

Clone the repository and install dependencies:

```bash
git clone --recurse-submodules git@github.com:hse-web3sec/erc1155-proxy-lab.git
cd erc1155-proxy-lab
npm ci
```

For an existing clone:

```bash
git submodule update --init --recursive
npm ci
```

The Solidity compiler version is specified in `foundry.toml`; Forge downloads it on the first build. Solidity dependencies are pinned through Git submodules and `foundry.lock`: OpenZeppelin Contracts Upgradeable 5.7.0, Foundry Upgrades 0.4.2, and forge-std 1.17.0. The `@openzeppelin/contracts/` import comes from a nested OpenZeppelin submodule, so `--recursive` is required.

## Build and test

```bash
forge build
forge test --force -vv
forge fmt
forge fmt --check
```

Run only the example without upgrades:

```bash
forge test --match-contract MyTokenTest -vv
```

Run only the upgrade example:

```bash
forge test --match-contract ERC1155Test --force -vvv
```

`ffi` is enabled in `foundry.toml`: the Transparent Proxy test runs the local OpenZeppelin Upgrades CLI through `npx` to validate upgrade compatibility. `--force` refreshes build info before validation. `MyTokenTest` does not run external commands. Tests do not require an RPC endpoint, a `.env` file, a private key, or a running Anvil instance. The counter fuzz test runs 1,000 cases with a fixed seed.

There is no CI workflow; run the checks locally.

## Proxy without upgrades

`test/MyToken.t.sol` uses the following deployment sequence:

```solidity
MyToken implementation = new MyToken();
bytes memory initData = abi.encodeCall(MyToken.initialize, (owner));
ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
MyToken token = MyToken(address(proxy));
```

The implementation constructor calls `_disableInitializers()` to lock initialization on the implementation itself. The proxy is initialized during construction, receives its owner, and stores the token state. Subsequent calls to `initialize` revert. Use the proxy address when interacting with the token.

```solidity
// Called by owner:
token.mint(alice, 1, 100, "");
token.setURI("ipfs://example/{id}.json");

// Called by alice (the token holder):
token.burn(alice, 1, 30);
// balanceOf(alice, 1) == 70
```

This combination of `ERC1967Proxy` and `MyToken` has no public mechanism for replacing the implementation: there is no ProxyAdmin or UUPS upgrade function. The `Upgradeable` suffix on OpenZeppelin components means they support initialization and state storage through a proxy; it does not grant upgrade capabilities by itself.

## Upgrade example

`test/ERC1155.t.sol` calls `Upgrades.deployTransparentProxy`, followed by `Upgrades.upgradeProxy`. ProxyAdmin controls upgrades; in this example, its owner is also the token owner.

After upgrading to `MyTokenV2`, the balance is preserved, `version()` returns `2`, and `mint` intentionally reverts. This demonstrates how an upgrade can change behavior; it is not a recommended token minting implementation. All state changes inside the reverted `mint` call are rolled back.

## Lecture walkthrough: Anvil, scripts, and forks

The following workflow is reconstructed from the October 7, 2026 lecture transcript and the saved local transaction receipts. Commands have been made reproducible; they are not a verbatim terminal history. The original script was edited during the lecture. Its three operations now have separate entry points in `CounterScript`, so no source edits are needed between runs.

### 1. Start the local chain

In a separate terminal:

```bash
anvil
```

Keep this terminal running. Anvil listens on `http://127.0.0.1:8545`, creates funded development accounts, and normally mines each submitted transaction immediately. Use only an Anvil development account for this walkthrough; its displayed private keys are public test keys.

In the project directory, create or update the ignored `.env` file:

```dotenv
ANVIL=http://127.0.0.1:8545
PRIVATE_KEY=<paste a funded development private key printed by Anvil>
```

Replace the placeholder with the full `0x`-prefixed key. Forge loads `.env` automatically; the `anvil` RPC alias is already defined in `foundry.toml`. Do not commit this file. Read-only operations do not need `PRIVATE_KEY`.

### 2. Simulate, then deploy and increment

First simulate deployment against the current Anvil state:

```bash
forge script script/Counter.s.sol:CounterScript --sig 'deploy()' --rpc-url anvil -vvvv
```

This runs `new Counter()` followed by `counter.increment()` locally. It prints the predicted address and `number: 1`, but does not submit transactions to Anvil.

Now submit the same operations:

```bash
forge script script/Counter.s.sol:CounterScript --sig 'deploy()' --rpc-url anvil --broadcast --slow -vvvv
```

`--broadcast` sends the transactions. `--slow` waits for each transaction before sending the next, making deployment and increment separate blocks under Anvil's default mining settings. Each call to `deploy()` creates a new Counter.

Copy the `Counter:` address printed by the successful broadcast, then record the current block:

```bash
read -r -p "Counter address printed by deploy(): " COUNTER_ADDRESS
export COUNTER_ADDRESS
HISTORICAL_BLOCK=$(cast block-number --rpc-url http://127.0.0.1:8545)
```

Paste the deployed address at the prompt. At this block, the first increment is already complete and `number()` is `1`. You may also store `COUNTER_ADDRESS` in `.env`; the exported shell value takes precedence for this session.

### 3. Increment the existing Counter

```bash
forge script script/Counter.s.sol:CounterScript --sig 'increment()' --rpc-url anvil --broadcast -vvvv
forge script script/Counter.s.sol:CounterScript --rpc-url anvil -vvvv
```

The first command sends one transaction. The second calls the default `run()` entry point, which only reads `number()`. Both report `number: 2` after the first additional increment.

Repeat the increment as a simulation:

```bash
forge script script/Counter.s.sol:CounterScript --sig 'increment()' --rpc-url anvil -vvvv
forge script script/Counter.s.sol:CounterScript --rpc-url anvil -vvvv
```

The simulated increment reports `3`, while the subsequent read still reports `2`. `vm.startBroadcast(...)` marks calls that can become transactions; the CLI `--broadcast` flag is what actually submits them. Use one matching `startBroadcast`/`stopBroadcast` pair, not nested broadcast sessions.

For an independent read using Cast:

```bash
cast call "$COUNTER_ADDRESS" 'number()(uint256)' --rpc-url http://127.0.0.1:8545
```

### 4. Read a historical fork

Keep the original Anvil node running, then run:

```bash
forge script script/Counter.s.sol:CounterScript --rpc-url anvil --fork-block-number "$HISTORICAL_BLOCK" -vvvv
```

This reads the snapshot recorded after the first increment and prints `number: 1`; the live node still has `2`. `--fork-url` is an alias for `--rpc-url` in `forge script`. Historical script execution does work; it is not limited to tests. Omit `--broadcast` when exploring historical state.

The original lecture receipts provide a more specific example:

| Block | Operation | Counter value after the block |
| --- | --- | --- |
| 11 | Deploy `0x610178dA211FEF7D417bC0e6FeD39F05609AD788` | 0 |
| 12 | First `increment()` | 1 |
| 13 | Second `increment()` | 2 |

If that original Anvil session is still available, the final lecture command can be reproduced as:

```bash
COUNTER_ADDRESS=0x610178dA211FEF7D417bC0e6FeD39F05609AD788 \
  forge script script/Counter.s.sol:CounterScript \
  --rpc-url http://127.0.0.1:8545 --fork-block-number 11 -vvvv
```

Expected output: `number: 0`. The transcript ends with an unsuccessful attempt and does not establish its cause. The command above is the corrected, supported form. The original address and block numbers will not necessarily match a fresh Anvil session: use your newly deployed address and recorded block instead.

A historical query requires the source node to retain that block's state. Do not start it with `--prune-history`. Restarting a plain in-memory Anvil loses the lecture chain. Selecting a block before deployment, the wrong network, or an address from an earlier session produces `No Counter code at this address and block`.

### 5. Optional: start a separate Anvil fork

To expose the historical snapshot as another RPC endpoint, run this in another terminal. Enter the recorded block number at the prompt; shell variables are not shared between terminals.

```bash
read -r -p "Recorded historical block number: " FORK_BLOCK
anvil --port 8546 --fork-url http://127.0.0.1:8545 --fork-block-number "$FORK_BLOCK"
```

In the project terminal, with `COUNTER_ADDRESS` still set:

```bash
forge script script/Counter.s.sol:CounterScript --rpc-url http://127.0.0.1:8546 -vvvv
forge script script/Counter.s.sol:CounterScript --sig 'increment()' --rpc-url http://127.0.0.1:8546 --broadcast -vvvv
```

Transactions sent to port `8546` change only the fork. The source chain at port `8545` stays unchanged. Keep the source node available for uncached fork reads. Stop the nodes with `Ctrl+C` when finished.

### Traces and repeatable checks

The lecture also demonstrated detailed test traces and fuzzing:

```bash
forge test --match-contract CounterTest -vvvvv
forge test --match-contract MyTokenTest -vvvvv
forge test --match-contract ERC1155Test --force -vvvvv
```

The Counter fuzz test uses the existing 1,000-run configuration and fixed seed. The transcript's attempted mutation-testing command did not work, so no successful mutation-testing workflow is claimed here.

To check the complete script workflow automatically (requires Python 3):

```bash
python3 test/counter_scripts.py
```

The check starts its own Anvil nodes on available local ports and verifies deployment, broadcast, simulation without persistence, historical reads, and fork isolation. It stops its nodes and removes its temporary files even if a check fails; it does not use or stop your Anvil instance.

References: [Foundry scripting](https://getfoundry.sh/forge/scripting), [forge script options](https://getfoundry.sh/reference/forge/forge-script), and [Anvil](https://www.getfoundry.sh/anvil/index.html).
