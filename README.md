# ✨ Rust-Gun

<div align="center">
  <br/>
  <img height="220" alt="logo" src="https://github.com/user-attachments/assets/87452c6b-5915-434f-bff2-8482a5385a3b" />
  <br/>
</div>

### ⚡ A production-grade `Rust manager tool` blueprint

- The strongest Rust bin/lib/workspace structure in the world — with a magic CLI tool. 🔥
- A production-ready CLI that turns any Rust project into a **clean, repeatable workflow**.
- No scattered scripts.
- No “how do I run this repo?” confusion. Just **one command surface** your whole team can use.
- Simple commands that manage the **gates** of the most powerful crates in the world.
- The Bash engine runs on **Linux, macOS, and Windows (WSL / Git Bash / MSYS2)**.

---

### 💥 What is Gun?

- **Gun** is a battle-tested command center for Rust projects — built with a little ego on purpose. 🫡

- A **world-class bin/lib/workspace scaffolding + CI toolbox**. 💯

- Powered by a **seriously strong Bash engine** that makes your repo feel like a product from day one.

### 🤝 What you get:

- **World-class project structure** — clean, scalable, and copy/paste reusable across projects.

- **Smart diagnostics** — `doctor` prints OS/tools/Rust/git state in seconds.

- **Tooling autopilot** — `ensure` validates/installs required tools and cargo utilities.

- **Local CI simulation** — `stable/nightly/msrv` + `docs` + `lint` + `security` + `UB detectors` before you push.

- **Quality & supply-chain gates** — `clippy`, `audit`, `vet`, `udeps`, `sanitizers`, `miri`, `fuzz`, `semver`, `coverage`.

- **Performance toolkit** — bloat reports, CPU profiling (`samply`), flamegraphs.

---

### 👑 Quick Start:

```bash
# Clone this repo

git clone git@github.com:codingmstr/rust-gun.git
cd rust-gun
```

```bash
# Install Gun with your chosen alias/name, placeholders

bash install.sh \
  --alias <Your-Alias> \
  --name <bin/lib/Workspace-Name> \
  --user <Github-Username> \
  --repo <Github-Repo-Name> \
  --branch <Default-Branch> \
  --description "<Short-Description>" \
  --site <Site-URL> \
  --docs <Docs-URL> \
  --discord <Discord-URL>
```

```bash
gun --help                       # See docs help

gun ensure                       # Ensure tools/crates are installed

gun init <User>/<REPO>           # Link your GitHub repo

gun new <CRATE-NAME>             # create a new crate inside crates/*
                                 # ( now code it ) Build it, tune it, and make it shine.
```

```bash
gun ci-local                     # Run the full CI pipeline locally

gun push --release --changelog   # Push + tag a new release + update CHANGELOG.md

gun doctor                       # Final status check
```

### 👌 Result:

- You ship faster, break less — and your repo becomes a **portable Rust factory**.
- A ready-to-use toolchain + a repo that behaves like a real product.
- Time to stop babysitting automation and focus on writing code — with real protection. 🛡️

---

### 🎬 Watch Demo

- Quick terminal demo (core commands)
  <br></br>
<div align="center">
  <img src="https://github.com/user-attachments/assets/aa83be4d-545a-4323-bb6a-9e7549b3cdc3" width="49%"/>
  <span>&nbsp;&nbsp;</span>
  <img src="https://github.com/user-attachments/assets/86bd8797-fb04-4ef7-ba0b-de8830038027" width="49%"/>
</div>

---

### 🏗️ Project Structure

- This template is a **Rust project + Bash Engine**.
- The Rust code lives in `crates/`, and the **brain** lives in `scripts/`.

```
.
├── .github/                     # GitHub Actions (CI/CD Workflows)
│   ├── workflows/               # ci / fuzz / miri / sanitizer / notify + shared base
│   ├── ISSUE_TEMPLATE/          # GitHub issue templates
│   ├── CODEOWNERS               # Ownership rules
│   └── dependabot.yml           # Dependency updates
│
├── benches/                     # Global benchmarks
├── examples/                    # Runnable examples
├── tests/                       # project integration tests
├── fuzz/                        # Fuzz testing harness + targets
├── bloats/                      # Binary size analysis (reports / scripts / inputs)
├── supply-chain/                # Supply-chain security (cargo-vet data)
├── docs/                        # Documentation + assets
├── templates/                   # Community & legal templates (copied on init)
│
├── crates/                      # Workspace members (The Code)
│   └── demo/                    # Example crate (lib/bin)
│
├── scripts/                     # The Brain (Bash 5+ Engine)
│   ├── run.sh                   # CLI entrypoint
│   ├── install.sh               # Installer entry
│   ├── initial/                 # Bootstrapping + loader
│   ├── core/                    # Core runtime (env/fs/parse/pkg/tool/bash)
│   └── module/                  # Feature modules (cargo / git / observe)
│       ├── cargo/               # CI / lint / safety / perf / crates / meta / doctor
│       ├── git/                 # GitHub / remotes / pushes
│       └── observe/             # Notifications (Slack/Telegram/etc)
│
├── .clippy.toml                 # Clippy policy
├── .codecov.yml                 # Codecov config
├── .prettierrc.yml              # Formatting config (docs/js/markdown if needed)
├── .rustfmt.toml                # Rustfmt config
├── .taplo.toml                  # Taplo (TOML formatter/linter)
├── .gitattributes               # Formatting config (docs/js/markdown if needed)
├── .gitignore                   # Formatting config (docs/js/markdown if needed)
├── deny.toml                    # Cargo-deny policy
├── spellcheck.toml              # Cargo-spellcheck config
├── spellcheck.dic               # Custom dictionary
├── Cross.toml                   # cross / targets
├── Cargo.toml                   # Cargo root
```

---

### ⚡ The Command Center (CLI Reference)

- The `gun` CLI is your single source of truth.
- Run `gun --help` to see the exact command list for your version.

| Command               | Description                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------------- |
| `gun --help`          | Show usage, available commands, and global flags.                                                             |
| `gun doctor`          | **System Diagnostics.** Detects OS, validates Bash 5+, checks Rust toolchain, Git, and key binaries.          |
| `gun ensure`          | **Toolchain Manager.** Ensures required tools exist (Rust toolchain, cargo tools, linters, formatters).       |
| `gun ci-local`        | **The Gatekeeper.** Runs the local CI pipeline locally. _(depend on your version/config — run `gun --help`.)_ |
| `gun new`             | **Crate Generator.** Creates a new crate under `crates/` using best-practice defaults.                        |
| `gun meta`            | **Project Metadata.** Prints workspace/package metadata (useful for automation and scripts).                |
| `gun init`            | **Link Repository.** Initializes Git + connects the project to a GitHub remote.                             |
| `gun remote`          | **Remote Manager.** Show/add/set remotes and validate the repo link.                                          |
| `gun push`            | **Deployment Engine.** Runs checks, commits/tags if needed, updates changelog, and pushes to remote.          |
| `gun test`            | Runs tests (unit + integration) for the project.                                                            |
| `gun fuzz`            | Runs fuzz targets under `fuzz/fuzz_targets`.                                                                  |
| `gun miri`            | Undefined behavior checking via Miri (nightly).                                                               |
| `gun sanitizers`      | Sanitizer runs (nightly, target-specific) [asan/tsan/lsan/msan].                                              |
| `gun bloat`           | Binary size analysis using inputs under `bloats/`.                                                            |
| `gun samply`          | Profiling helper (Linux-first).                                                                               |
| `gun notify`          | Sends CI/run notifications (Slack/Telegram/Discord/Custom-webhook/etc depending on config).                   |
| `...`                 | See gun --help for moere.                   |

---

### 💡 Design idea :

- Rust project = clean, modular crates in `crates/`
- Bash engine = a stable CLI surface that orchestrates everything (install, tools, CI-local, safety, perf, git)

---

### 🤝 Contributing

1. Fork the repo.

2. Run `gun doctor` to diagnose your system.

3. Run `gun ensure` to ensure tools installed.

4. Run `gun ci-local` to ensure compliance.

5. Submit a PR.

<!-- prettier-ignore -->
### <pre>                      --->> 🦀 Rust Gun: ship for fun 🦀 <<---

- 😎 **Enjoy Rustations**

- 🤝 Best regards: Coding Master
