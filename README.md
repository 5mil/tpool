# thimble

A window that thinks it is 1999, a host that keeps the screen names, and a pool that takes a chain source if you give it one.

Repository: https://github.com/5mil/tpool

The page dials. The host is the thing you leave running. The name on the window, the binary, and the files is thimble. It is a nod to the old sign-on, welcome, and mail. It is not that company.

## What you are running

| Program | Where | What it does |
|---|---|---|
| `thimble` / `ThimbleServer.exe` | The machine you leave on | Sign-on on 8080. Pool on 3333–3338. Setup on first start. Report window on Windows. The same menu on Linux. |
| `Thimble.exe` | A Windows machine | Sign up, sign on, chat, mail, Start rig. |
| `thimble-miner` | Linux, macOS, or Windows | A worker that connects to a pool port. |
| Browser | Anywhere | http://HOST:8080 for sign-on. http://HOST:8080/admin for a coin fetch. |

Files the host writes next to itself:

| File | What it is |
|---|---|
| `host.cfg` | Admin token, pay threshold, optional RPC, upstream, and wallet. Written on first start. |
| `thimble.db` | Members and mail. |
| `party.db` | Shares and balances. |
| `pools.cfg` | Modules. The port stays closed until a module has a template. |
| `payouts.cfg` / `payouts.log` | Balances, then the txid when a send succeeds. |
| `coin.cfg` | Last fetched coin. |

`THIMBLE_ADMIN`, `THIMBLE_PAY_SATS`, `THIMBLE_RPC`, `THIMBLE_UPSTREAM`, and `THIMBLE_WALLET` override `host.cfg` when they are set. You do not have to export them to start.

## First start

Run the host with no `host.cfg` beside it.

- It writes `host.cfg` with an admin token and a payout threshold of 100000 sats.
- On Linux, macOS, and the other Unix hosts, it prints the token once. On Windows, Thimble - Setup shows it in the token field. Save and open host, or close the window and the generated token stays.
- Pool ports stay closed. Nothing is mined, and nothing is paid, until a module has one chain source and that source can serve a template.
- The Linux menu is `1 report`, `2 check this host`, `3 settings`, `4 quit`. Settings is the same fields as the Windows window: admin, pay, upstream, rpc, wallet, add module.
- `./thimble --setup` asks again. On Windows, `--setup` opens Thimble - Setup even when `host.cfg` already exists.
- `./thimble --check` does not create `host.cfg`. It loads one if it is there.

Keep `host.cfg` private. The admin token is what `/admin` asks for.

## Get Zig

Zig 0.17.0, the current stable release. https://ziglang.org/download/

Check with `zig version`. The distro package is often older than 0.17. If `zig version` is not 0.17, use the tarball from ziglang.org.

## Windows

Prebuilt x86_64 binaries are in `windows/` on this repository. They are the ReleaseSafe build. You do not need Zig to run them.

| File | What it is |
|---|---|
| `windows/ThimbleServer.exe` | The host. First start opens Thimble - Setup, then Thimble - Host. |
| `windows/Thimble.exe` | The client. Sign up, sign on, chat, mail, Start rig. |
| `windows/thimble-miner.exe` | A worker. Console window. Point it at the host. |

### Server

From a clone, double-click `windows\ThimbleServer.exe`, or from `cmd` in that folder:

```
ThimbleServer.exe
```

To build it yourself, from a checkout, with Zig 0.17 on PATH:

```
zig build-exe src/server.zig -target x86_64-windows-gnu -OReleaseSafe -lc -luser32 -lgdi32 -lcomctl32 --subsystem windows -femit-bin=ThimbleServer.exe
```

Or `zig build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe`, which also builds `thimble` for the host you are on.

Start it:

```
ThimbleServer.exe
```

The first window is Thimble - Setup. After that, the window is Thimble - Host. Pool → Settings is the module list. Pool → Check this host is the same check as `./thimble --check`. Settings write `pools.cfg`. A module listens on the next start, and only after its source has a template.

You can still set variables before start. They override the file. In `cmd`:

```
set THIMBLE_ADMIN=choose-eight-or-more
set THIMBLE_UPSTREAM=pool.example.com:3333
ThimbleServer.exe
```

In PowerShell:

```
$env:THIMBLE_ADMIN = "choose-eight-or-more"
$env:THIMBLE_UPSTREAM = "pool.example.com:3333"
.\ThimbleServer.exe
```

Firewall: allow inbound TCP 8080 (sign-on) and the pool port you actually turned on (3333 for Bitcoin) if friends connect from other machines.

### Client

`windows\Thimble.exe` is already built. `Launch Thimble.bat` at the top of the checkout starts it. To build it yourself:

```
zig build-exe src/client.zig -target x86_64-windows-gnu -OReleaseSafe -lwinhttp --subsystem windows -femit-bin=Thimble.exe
```

Run `windows\Thimble.exe`, or `Launch Thimble.bat` at the top of the checkout. Host box is the server machine (`127.0.0.1` if it is this PC). Port box is `8080`. Sign Up once, then Sign On. Start rig uses the worker name (`Kitchen.rig1`) and talks to the pool port for that coin (3333 for Bitcoin).

The worker, from `windows\`:

```
thimble-miner.exe --host 127.0.0.1 --port 3333 --worker Kitchen.rig1
```

## Linux

One set of commands. The package line is the only part that changes.

### Debian, Ubuntu, Mint, Pop

```
sudo apt update
sudo apt install -y git build-essential
```

Install Zig 0.17 from ziglang.org. Then:

```
git clone https://github.com/5mil/tpool.git
cd tpool
zig build-exe src/server.zig -OReleaseSafe -lc -femit-bin=thimble
./thimble
```

Open http://127.0.0.1:8080

Leave it up with systemd. `/etc/systemd/system/thimble.service`:

```
[Unit]
Description=thimble host
After=network.target

[Service]
WorkingDirectory=/opt/thimble
ExecStart=/opt/thimble/thimble
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Put the binary, and let the first start write `host.cfg`, in `/opt/thimble`. If you already have a token, copy `host.cfg` there and `chmod 600 host.cfg`.

```
sudo systemctl enable --now thimble
```

The menu needs a terminal. A service has no menu. Use `http://127.0.0.1:8080/admin` and `curl http://127.0.0.1:8080/api/doctor`, or run `./thimble --check` from `WorkingDirectory`.

### Fedora, RHEL, CentOS Stream

```
sudo dnf install -y git gcc
```

Zig 0.17 from ziglang.org. Same clone, build, and systemd unit as Debian.

### Arch, Manjaro, Endeavour

```
sudo pacman -S --needed git base-devel zig
```

Arch’s `zig` is often current. If `zig version` is not 0.17.0, use the ziglang.org tarball. Same clone and build as Debian. systemd unit is the same.

### openSUSE

```
sudo zypper install -y git gcc
```

Zig 0.17 from ziglang.org. Same clone and build.

### Alpine

```
apk add git build-base
```

Zig 0.17 from ziglang.org. Same clone and build. OpenRC instead of systemd, `/etc/init.d/thimble`:

```
#!/sbin/openrc-run
name="thimble"
command="/opt/thimble/thimble"
command_background=true
pidfile="/run/thimble.pid"
directory="/opt/thimble"
```

```
chmod +x /etc/init.d/thimble
rc-update add thimble default
rc-service thimble start
```

### Nix

With Nix on any distro:

```
nix-shell -p zig git
git clone https://github.com/5mil/tpool.git
cd tpool
zig build-exe src/server.zig -OReleaseSafe -lc -femit-bin=thimble
./thimble
```

NixOS, in `configuration.nix` or a module:

```
environment.systemPackages = with pkgs; [ zig git ];
```

Or a shell app that only launches a binary you already built:

```
pkgs.writeShellScriptBin "thimble" ''
  cd /var/lib/thimble
  exec ./thimble
''
```

Build the binary once with `zig build-exe` and point the service at it. Nix does not need to package the Zig sources for the host to run. `host.cfg` still lives in the working directory.

## macOS

```
brew install git
```

Zig 0.17 from ziglang.org (the Homebrew formula lags). Then the same clone and build as Debian:

```
git clone https://github.com/5mil/tpool.git
cd tpool
zig build-exe src/server.zig -OReleaseSafe -lc -femit-bin=thimble
./thimble
```

There is no native Mac window. Use the browser at http://127.0.0.1:8080. The menu is the same as Linux. To leave it up, a LaunchDaemon or `brew services` is unnecessary for a friend: run it in a terminal, or `nohup ./thimble >/tmp/thimble.log 2>&1 &` after the first start has written `host.cfg` (run it once in the foreground, quit with `4`, then start it again).

## FreeBSD

```
pkg install git
```

Zig 0.17 from ziglang.org. Same clone and build. An `/etc/rc.d` script can run `/usr/local/thimble/thimble` with `thimble_chdir`. The menu and `host.cfg` behave as on Linux.

## Client on Linux, macOS, and FreeBSD

There is no native window outside Windows. Use the browser.

http://SERVER:8080

Sign up, sign on, pick a room, send. Mail is on the same host.

A worker is `thimble-miner`:

```
zig build-exe src/miner.zig -OReleaseSafe -lc -femit-bin=thimble-miner
./thimble-miner --host 127.0.0.1 --port 3333 --worker Kitchen.rig1 --threads 4 --device cpu
```

Leave `--threads` and `--device` off and it counts CPUs and looks for `/dev/nvidia0`, `/dev/dri/card0`, and `/dev/ttyUSB0`.

## Configuration

`host.cfg`, written on first start:

```
admin=the-token-printed-once
pay_sats=100000
rpc=
upstream=
wallet=
```

| Key | Meaning |
|---|---|
| `admin` | 8 or more characters. The `/admin` page asks for it. |
| `pay_sats` | Send a balance at this many satoshis. |
| `rpc` | Optional. `http://user:pass@127.0.0.1:8332`. One chain source. |
| `upstream` | Optional. `host:3333`. Jobs come from that pool. Do not set this and `rpc` together. The check fails if both are set. |
| `wallet` | Optional coinbase address for the template you build. |

The same names as environment variables: `THIMBLE_ADMIN`, `THIMBLE_PAY_SATS`, `THIMBLE_RPC`, `THIMBLE_UPSTREAM`, `THIMBLE_WALLET`. A set variable wins over the file.

A port stays closed until that module has a real template. sha256d and scrypt shares are checked against the job target. Anything else is refused with `algorithm not checked yet`. A share that misses the target is `does not meet target`. A stale job id is `stale job`.

A block is counted only when the hash meets the network target and the node accepts `submitblock`, or the upstream pool accepts that submit. The party is paid the subsidy (coinbase value minus transaction fees), then the house percent. The transaction fees are not paid out. Balances sit until the pay threshold. The worker name must be a base58 or bc1 address, or `address.worker`. A successful send is appended to `payouts.log` and the balance is cleared. A refused send is put back.

Build and open pool starts the coin's node if the build produced one, pruned, on 127.0.0.1. The report shows the sync height. The port opens when `getblocktemplate` succeeds. Each module has its own node or upstream, so two coins can run together. Merge-mine pays a second subsidy only if the child node accepts `submitauxblock`.

Neither upstream nor RPC, and no node started: the report says the port is closed.

`pools.cfg`, written by Settings or by hand. See `pools.cfg.example`.

```
Bitcoin	sha256d	3333	1	Namecoin	5
Litecoin	scrypt	3334	1	Dogecoin	0
#house	1
#data	all
```

Columns: name, algorithm, port, on (`1`/`0`), merge child, bonus percent. The Windows settings window also stores a source and a wallet on the line. `#house 1` starts the house worker when a chain source is connected. Two lines with `1` are two listeners. A module added from the Linux menu is saved off. Set the on column to `1` and restart.

Pool ports:

| Port | Algorithm |
|---|---|
| 3333 | sha256d |
| 3334 | scrypt |
| 3335 | ethash |
| 3336 | kawpow |
| 3337 | randomx |
| 3338 | yescrypt |

Only sha256d and scrypt are checked. The other ports exist so a module can be named. They refuse a share with a reason.

Worker name is `screen.rig`. The text before the dot is the party. `asic` or `gpu` in the password marks the device.

## Check it

The check proves the share math, then says whether this host can actually take a miner. A failure means do not point hardware at it yet. A warning means it can run, and something is still missing.

From the directory that holds `host.cfg`, without leaving the window up:

```
./thimble --check
```

Exit code 0 means no failures. Exit code 1 means at least one FAIL line. Warnings do not fail the process.

On the running host:

```
curl -s http://127.0.0.1:8080/api/doctor
```

Windows: the button **Check this host**, or Pool → Check this host. The report stays on that result until Refresh. The menu on Linux is `2`.

What it looks at:

| Check | Pass means |
|---|---|
| `hash.genesis` / `hash.scrypt` | Double-sha256 and scrypt match the real genesis blocks. |
| `share.easy` / `share.hard` / `share.reject` | A regtest header counts. A hard header is not waved through. ethash, a missing template, and bad hex are refused with different reasons. |
| `pay.subsidy` / `pay.party` / `pay.mature` | Height 0 is 50 BTC, not a flat million. The house keeps 1%. Credit waits 100 blocks. |
| `files.write` | Atomic rename works, so the ledgers can save. |
| `module.*` | Each running module is sha256d or scrypt, has one chain source, and does not put a git URL in the jobs field. |
| `live.*` | This process has a template, or it says why the port is still closed (including a node still downloading). |
| `dial.*` | The node on 127.0.0.1 answered `getblockchaininfo`, or the upstream pool spoke stratum. Other addresses are reported, not dialed, so a dead host cannot stall the check. Names are not resolved. |
| `port.*` | A port with a template is listening. A port without one stays closed. |
| `env.admin` | A token of 8 or more characters is in the environment or in `host.cfg`. |

Under `--- recent shares ---` is every submit this process has seen: share, block, block-unconfirmed, low, stale, bad, algo, or upstream. `block-unconfirmed` met the network target and the node or the upstream pool did not accept it. The note is the node's reason.

`./thimble --selftest` still signs up, posts, and sends mail, and it fails if the share math itself is wrong.

```
curl -s http://127.0.0.1:8080/api/health
curl -s http://127.0.0.1:8080/api/pool
```

Health returns users, sessions, messages, accepted shares, workers. The report window shows the chain line, one line per module, and the last check summary.

## Show a friend

On the host machine, tunnel 8080 (and the pool port if they will mine):

```
cloudflared tunnel --url http://127.0.0.1:8080
```

On Windows that button is in Thimble - Settings: Open free tunnel. It publishes the sign-on page only. Publish mining port is separate. The Cloudflare button cannot carry the stratum port.

Or `ngrok http 8080`. Give them the URL. They sign up in a browser. A miner points `--host` at that name and `--port` at the pool port you also exposed.

## Coin fetch

http://127.0.0.1:8080/admin with the token from `host.cfg` (or `THIMBLE_ADMIN`). Repo must be `https://github.com/` or `https://gitlab.com/`. The host clones into `coin-src/` and writes `coin.cfg`. It does not compile the validator. The Windows Settings window is the path that builds and opens a pool from the known coin list, or from a repo you paste.
