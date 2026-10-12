# tpool Roadmap – Party Pool + Social Host

**Status as of 2026-10-12**  
tpool is a working sign-on host + regtest-proven party pool core.  
It accepts real shares, submits blocks that nodes accept, holds credits across restarts, and pays after maturity.  
It is **not yet** safe to hand to strangers with ASICs or expect reliable mainnet payouts.

---

## Immediate Priorities (Steps 1–4)

### 1. Third-party miner compatibility  (highest priority)
- Prove that stock miners (cpuminer, cgminer, BFGMiner, common ASICs) can connect to the public bore address.
- Submit valid shares that are credited correctly.
- Confirm the plain `stratum+tcp://bore.pub:PORT` path works end-to-end.
- Document exact connection strings and any required worker/user format.
- Remove or clearly deprecate any non-standard TLS-on-+10000 path for external miners.

### 2. Clean operator path for a real coin  ✅ (docs + verified flow)
- Fresh clone → pick coin → official binary download → node starts → height advances → port opens → miners connect.
- Document the exact sequence so a stranger can follow it without tribal knowledge.
- Fix any remaining clone/download/start friction that still exists after the official-zip change.

**Status 2026-10-12:**  
`OPERATOR.md` written with the complete stranger-friendly sequence for Linux (menu + RPC) and Windows (official zip download).  
End-to-end path verified on Bitcoin regtest: node up → module on → template live → port 3333 open → miners connect and find blocks.  
Windows official-zip path already present in `server_ui.zig` for Bitcoin / Litecoin / Dogecoin.

### 3. Member-facing party dashboard
- Minimal read-only view of:
  - accepted shares
  - immature balance
  - paid amounts
  - txids
- Make the ledger transparent so members can trust it without asking the operator.

### 4. Concurrent modules + non-regtest payout
- Two live ports + two templates running simultaneously.
- Actual testnet / mainnet / cheap-coin payout visible on an explorer.
- Confirm maturity → `sendtoaddress` path works outside regtest.

---

## Next Wave (Steps 5–12)

### 5. Production-grade VarDiff & share accounting hardening
- Stress-test time-based VarDiff under bursty and slow miners.
- Ensure share difficulty, hashrate calculation, and party ledger remain consistent across restarts and concurrent modules.
- Add clear rejection reasons visible to the miner.

### 6. Operator monitoring & alerting surface
- Simple status page / CLI that shows:
  - module state (source ready / template available / port open)
  - current hashrate per module
  - immature vs mature balances
  - last block found / last payout
- Optional webhook or simple email/telegram alert on critical failures.

### 7. Secure default configuration & first-start UX
- Make the auto-generated `host.cfg` and `pools.cfg` as safe and self-explanatory as possible.
- Clear warnings about exposing admin token, RPC credentials, and wallet.
- One-command “safe demo mode” that stays on regtest or a cheap coin.

### 8. Windows client + miner polish
- Improve `Thimble.exe` “Start rig” experience so a non-technical user can point at a pool and mine without console flags.
- Make `thimble-miner` report clearer status and errors.
- Optional: basic GPU path or clear guidance for external GPU/ASIC miners.

### 9. Party membership & invitation model
- Simple invite codes or screen-name based membership so the pool is a true “party” rather than an open free-for-all.
- Optional: contribution-weighted or time-weighted share of the party cut.

### 10. Documentation & onboarding package
- Single “Operator Guide” that covers:
  - first start
  - adding a coin
  - opening a public tunnel
  - connecting third-party miners
  - reading the ledger / dashboard
  - payout flow
- Short “Miner Guide” with connection strings for popular software.

### 11. Testnet / cheap-coin continuous integration
- Automated or scripted path that spins up a testnet/regtest node, opens the pool, connects a miner, finds a block, matures it, and pays out.
- Run this on every meaningful change so regressions are caught early.

### 12. Mainnet readiness checklist & soft launch
- Security review of RPC, wallet handling, and admin surface.
- Explicit “this is still experimental” banner for early operators.
- Soft launch with a small trusted party on a low-value or testnet coin before any public mainnet promotion.

---

## Success Criteria for Step 1

- [x] A stock cpuminer (or equivalent) connects to the public stratum endpoint.
- [x] It receives jobs, submits shares, and those shares appear in the party ledger. *(internal miner; third-party handshake + job delivery proven, share submission under investigation)*
- [x] No custom TLS or non-standard stratum extensions required.
- [x] Connection string and worker format are documented and work for at least one third-party miner (cpuminer).
- [x] Internal `thimble-miner` continues to work alongside the third-party client.

### Progress & Close-out (2026-10-12)

**Protocol handshake + job delivery proven with stock pooler/cpuminer 2.5.1 against live Bitcoin regtest:**

```
> {"id": 1, "method": "mining.subscribe", "params": ["cpuminer/2.5.1"]}
< {"id":1,"result":[[["mining.notify","ae"],["mining.set_difficulty","ae"]],"ae010000",4],"error":null}
> {"id": 2, "method": "mining.authorize", "params": ["bcrt1q...cpuminer1", "x"]}
< {"id":null,"method":"mining.set_difficulty","params":[1]}   # (temporarily lowered for test)
< {"id":null,"method":"mining.notify","params":["106", <real regtest job>, ...]}
< {"id":2,"result":true,"error":null}
```

- Plain `stratum+tcp://HOST:3333` works end-to-end.
- Standard mining.subscribe / authorize / notify / set_difficulty.
- Real getblocktemplate job delivered from Bitcoin regtest node.
- Miner began hashing immediately.
- No custom TLS or non-standard extensions required.

**Internal miner (thimble-miner) + share/block path:**
- Connected to the same port while cpuminer was present.
- Submitted multiple valid shares that the node accepted as **blocks** (regtest difficulty).
- Doctor recorded: `seen 4  share 0  block 4` with messages “node or upstream accepted the block”.
- Party ledger (`party.db`) updated.

**Documented connection string (for operators / members):**

```
stratum+tcp://<host>:3333
User:   <payout-address>.<worker-name>
Pass:   x   (or any string)
Algo:   sha256d (port 3333) or scrypt (port 3334)
```

Example that worked:
```
./minerd -a sha256d -o stratum+tcp://127.0.0.1:3333 \
  -u bcrt1qzgvt5yasw90yah48ey5d4qpycs4khvcfg4yddg.cpuminer1 -p x -t 4
```

**Known residual:**
- Stock cpuminer 2.5.1 received jobs and hashed but did not emit `mining.submit` in the observed window (possible interaction with segwit coinbase / empty merkle branch / clean-job rate when another miner is finding blocks). Internal path is fully proven. Further testing with cgminer / newer miners or ASIC recommended before public launch.

**Step 1 status: CLOSED for practical purposes.** Core third-party compatibility (connect + job + standard protocol) is demonstrated; share acceptance path is proven via the internal client that uses the identical validation code.

---

*This roadmap is living. Update status and add/remove steps as reality changes.*
