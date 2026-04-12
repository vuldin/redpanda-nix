# Which Redpanda Build Should I Use?

This project provides five Redpanda packages. Use this guide to choose the right one.

## Quick Decision Tree

```
Need CMVP-certified FIPS?
├─ YES → redpanda-fips (NIST-certified deb extraction)
│
└─ NO → Need maximum compliance provenance (SLSA L3)?
   ├─ YES → redpanda (source build, ~1-4 hours)
   │
   └─ NO → Need fast builds?
      ├─ YES → redpanda-deb (deb extraction, ~5 min)
      │
      └─ Just need the CLI? → redpanda-rpk
```

## The Packages

### 1. `redpanda` (Default) — Source Build from Bazel

**SLSA Build L3 (self-assessed) | Full provenance | Complete SBOM**

The default package builds Redpanda from source using Bazel inside a hermetic Nix sandbox. This provides the strongest possible supply chain provenance — every byte is traceable from git tag to final binary.

Adapted from [redpanda-data/redpanda#29919](https://github.com/redpanda-data/redpanda/pull/29919) by [randomizedcoder](https://github.com/randomizedcoder).

```bash
nix build .#redpanda
```

**Use this if:**
- You need SLSA Build L3 provenance
- You need complete SBOMs (all compiled-in C++ libraries visible)
- You're targeting DoD SBOM Management, NIST 800-161 SR-4, or CJIS supply chain requirements
- You can afford ~1-4 hour build times (cold build)

**Build time:** ~1 hour (22 cores), ~4 hours (4 cores, CI free-tier)

**Note:** This build does **not** include [PGO (Profile-Guided Optimization)](https://www.redpanda.com/blog/supercharging-streaming-profile-guided-optimization). Redpanda's official binaries are compiled with PGO + LTO, which yields ~47% lower p999 latencies. If production performance is your priority, use `redpanda-deb` instead.

---

### 2. `redpanda-deb` — Deb Package Extraction

**Fast fallback | SLSA L1 | PGO + LTO optimized | 5 minute builds**

Extracts official pre-built binaries from Redpanda's deb packages on Cloudsmith CDN. SHA256-verified but the binary provenance stops at the publisher — you trust Redpanda's build pipeline. These binaries include PGO and LTO optimizations from Redpanda's release pipeline.

```bash
nix build .#redpanda-deb
```

**Use this if:**
- You want fast installation (5 minutes)
- SLSA L1 (provenance exists) is sufficient
- You're doing development/testing and don't need full provenance
- You need the NixOS module to start quickly

---

### 3. `redpanda-fips` — CMVP-Certified FIPS 140-2

**NIST CMVP cert #4985 | FedRAMP High | DoD IL4/IL5**

Uses Redpanda's official FIPS deb packages containing NIST-certified OpenSSL FIPS modules. Building FIPS from source does NOT carry the same CMVP certification — the certification is attached to the specific binary, not the source code.

```bash
nix build .#redpanda-fips
```

**Use this if:**
- You need FedRAMP High compliance
- You need NIST CMVP-validated FIPS 140-2 cryptography
- You're deploying to DoD IL4/IL5 environments
- A contract requires FIPS certification (not just FIPS-mode configuration)

**10-30% performance overhead** from FIPS validation.

---

### 4. `redpanda-rpk` — Standalone CLI

**Go binary | Independent from server build**

Builds just the `rpk` CLI tool via Go's `buildGoModule`. Useful when you only need the management CLI without the server.

```bash
nix build .#redpanda-rpk
./result/bin/rpk cluster info
```

---

### 5. `redpanda-image` / `redpanda-image-debug` — OCI Container

**~313 MB minimal | Pipe to docker load**

Minimal OCI container image built with `dockerTools.streamLayeredImage`. Debug variant adds bash and coreutils.

```bash
nix build .#redpanda-image && ./result | docker load
docker run -p 9092:9092 -p 9644:9644 redpanda:nix
```

---

## Comparison Matrix

| Feature | `redpanda` | `redpanda-deb` | `redpanda-fips` | `redpanda-rpk` |
|---------|------------|----------------|-----------------|----------------|
| **Build time** | 1-4 hours | 5 min | 5 min | 2 min |
| **Source** | Bazel from git tag | Official deb | Official FIPS deb | Go from git tag |
| **SLSA level** | **L3** (self-assessed) | L1 | L1 | L1 |
| **SBOM completeness** | Full (all compiled libs) | Partial (wrapper only) | Partial (wrapper only) | Full (Go modules) |
| **Provenance** | Git → Bazel → Nix store | Cloudsmith URL + SHA256 | Cloudsmith URL + SHA256 | Git → Go → Nix store |
| **FIPS 140-2** | No | No | **CMVP certified** | No |
| **FedRAMP High** | No (no FIPS) | No (no FIPS) | **Yes** | N/A |
| **PGO optimized** | No | **Yes** | **Yes** | N/A |
| **Custom patches** | Yes | No | No | Yes |
| **NixOS module** | Yes | Yes | Yes | N/A |

---

## Common Questions

### Q: Why is the source build the default if it takes hours?

**A:** Compliance. The source build provides SLSA Build L3 provenance, complete SBOMs, and full source-to-binary traceability. These are increasingly required for DoD procurement and federal supply chain security. The deb fallback exists for fast iteration — use `nix build .#redpanda-deb` when you need speed.

### Q: Is `redpanda-deb` less secure than `redpanda`?

**A:** No. Both produce the same Redpanda software. The difference is in **provenance assurance** — how much you can prove about how the binary was built. `redpanda-deb` trusts Redpanda's build pipeline; `redpanda` builds everything from source in an auditable sandbox.

### Q: Does the source build include PGO (Profile-Guided Optimization)?

**A:** No. Redpanda's official release pipeline uses a multi-stage [PGO build process](https://www.redpanda.com/blog/supercharging-streaming-profile-guided-optimization): an instrumented build runs representative workloads on a 3-node cluster, collects branch/call-frequency profiles, then recompiles with those profiles applied. This yields significant performance gains — Redpanda reports **47% lower p999 latencies** and **~50% lower p50 latency** from PGO.

The Nix source build performs a single-pass compilation without PGO profiles. The official deb packages (`redpanda-deb`, `redpanda-fips`) are built through Redpanda's full pipeline and include PGO + LTO optimizations.

**Choose based on your priorities:**
- **Maximum performance** → `redpanda-deb` (PGO + LTO optimized by Redpanda's pipeline)
- **Maximum provenance** → `redpanda` (SLSA L3, full source-to-binary traceability, no PGO)

PGO profiles are source-level (LLVM IR), so they are portable across build systems. If Redpanda publishes `.profdata` files as release artifacts in the future, the source build could apply them via `--fdo_optimize` to get both full provenance and PGO performance.

### Q: Can I switch between packages?

**A:** Yes. All packages install compatible binaries. Data directories are compatible. The NixOS module works with any package via `services.redpanda.package`.

### Q: When do I actually need FIPS?

**A:** Only when contractually or legally required:
- FedRAMP High environments
- DoD IL4+ (classified networks)
- Government contracts specifying FIPS 140-2
- State/local government mandates (rare)

FIPS is about **certification**, not additional security. Standard OpenSSL is cryptographically secure.
