# tpool Operator Guide – Standing Up a Coin

This is the clean path a stranger can follow without tribal knowledge.

## Prerequisites

- Zig 0.17 (or use the prebuilt `windows/` binaries on Windows)
- A machine that can run a full or pruned node (or point at an upstream stratum)
- For public mining: ability to open a tunnel (bore / Cloudflare) or port-forward

## 1. Clone and first start

```bash
git clone https://github.com/5mil/tpool.git
cd tpool
# Linux / macOS
zig build-exe src/server.zig -OReleaseSafe -lc -femit-bin=thimble
./thimble
```

On first start the host writes `host.cfg` with a generated admin token.  
Save that token. It is required for `/admin`.

On Windows, just run `windows\ThimbleServer.exe`. The Setup window appears.

## 2. Add a module (the “pick coin” step)

### Linux / menu path

From the host menu choose `3 settings` → `f add module`.

You will be asked for:

| Field     | Example                                      | Notes |
|-----------|----------------------------------------------|-------|
| name      | Bitcoin                                      | Free text, ≤ 32 chars |
| algorithm | sha256d                                      | Only `sha256d` or `scrypt` are validated today |
| port      | 3333                                         | ≥ 1024 |
| source    | `http://user:pass@127.0.0.1:18443`           | RPC URL **or** `host:port` upstream stratum |
| wallet    | `bcrt1q…` or `bc1q…` or base58               | Coinbase + payout address |

The module is written to `pools.cfg` with `on=0`.  
Edit the file and change the on-column to `1`, then restart the host.

Example `pools.cfg` line after editing:

```
Bitcoin	sha256d	3333	1	none	0	http://thimble:thimble@127.0.0.1:18443	bcrt1qzgvt5yasw90yah48ey5d4qpycs4khvcfg4yddg
```

### Windows GUI path

Pool → Settings → add module.  
For Bitcoin / Litecoin / Dogecoin the host can download the **official** Windows zip (bitcoincore.org / litecoin.org / dogecoin releases) and launch the node automatically.  
That path is already implemented and prefers official binaries over “make”.

## 3. Start (or point at) a node

### Option A – local regtest / testnet / mainnet node (recommended for first proof)

```bash
# Bitcoin Core example (regtest)
bitcoind -regtest -rpcuser=thimble -rpcpassword=thimble -rpcport=18443 -daemon
bitcoin-cli -regtest -rpcuser=thimble -rpcpassword=thimble createwallet pool
ADDR=$(bitcoin-cli -regtest -rpcuser=thimble -rpcpassword=thimble -rpcwallet=pool getnewaddress)
bitcoin-cli -regtest -rpcuser=thimble -rpcpassword=thimble generatetoaddress 101 $ADDR
```

Then set the RPC source in the module (or via `THIMBLE_RPC` / host.cfg) to:

```
http://thimble:thimble@127.0.0.1:18443
```

### Option B – upstream stratum

Set the module source to an existing pool address, e.g. `pool.example.com:3333`.  
The host will proxy templates; party accounting still happens locally.

### Option C – Windows official download

In the Windows Settings UI, choose Bitcoin / Litecoin / Dogecoin.  
The host downloads the official zip, extracts, and launches the daemon.  
No compile step.

## 4. Watch until the port opens

```bash
./thimble --check
# or
curl http://127.0.0.1:8080/api/doctor
```

You want to see:

- `module.Bitcoin … jobs come from one pool or one node`
- `live.Bitcoin template height N … ready. miners can be given a job`
- `port.3333 port 3333 is accepting miners`

The pool port stays closed until `getblocktemplate` (or the upstream) returns a usable job.  
It does **not** wait for full IBD; a pruned node that can answer templates is enough.

## 5. Connect a miner

```
stratum+tcp://<host>:3333
User:   <payout-address>.<worker-name>
Pass:   x
```

Example with stock cpuminer:

```bash
./minerd -a sha256d -o stratum+tcp://127.0.0.1:3333 \
  -u bcrt1qzgvt5yasw90yah48ey5d4qpycs4khvcfg4yddg.worker1 -p x -t 4
```

Internal worker:

```bash
./thimble-miner --host 127.0.0.1 --port 3333 \
  --worker bcrt1q…internal1 --threads 4 --device cpu
```

## 6. Verify shares and ledger

```bash
./thimble --check
# or look at party.db / the doctor “recent shares” section
```

**Member dashboard (read-only):** open `http://HOST:8080/party`  
Shows workers (shares, hashrate, immature, balance) and recent payouts with txids. No login required. Data comes from `/api/pool`.

Accepted shares move into the party ledger.  
After 100 confirmations the credit becomes mature and can be paid via `sendtoaddress` once the balance exceeds the threshold in host.cfg.

## Common failure modes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Port never opens | No template yet | Node still downloading, or RPC credentials wrong, or source blank |
| “no job” / stale | Template height moving too fast or clean-jobs | Normal on regtest with another miner finding blocks |
| Doctor WARN about zero peers | Isolated regtest | Expected; blocks will not relay |
| Module saved but still off | `on` column is 0 | Edit pools.cfg → 1 and restart |
| Admin refuses | Missing / wrong token | Check host.cfg or THIMBLE_ADMIN |

## Security notes

- Never commit `host.cfg`. It contains the admin token.
- Prefer a dedicated wallet address for the pool coinbase.
- On mainnet start with a very small trusted party and a high pay threshold.
- Keep the node’s RPC bound to localhost or protected by a firewall.

---

This document is the concrete answer to “what does a stranger actually type?”.  
Update it whenever the Settings UI or module format changes.
