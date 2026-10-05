# AGENTS.md

Ansible-managed dotfiles for a personal Arch Linux machine. One role per tool;
configs live in the repo and are symlinked into `~/.config`.

## Commands

```bash
ansible-galaxy collection install -r requirements.yml   # once; installs kewlfft.aur
ansible-playbook local.yml                              # apply everything this host enables
```

`local.yml` is the only real entrypoint. `setup.yml` is a stale leftover (last touched
2026-05) that predates the role structure: not referenced by the README, by
`local.yml`, or by any role, and its package list duplicates what roles install.
Don't treat it as part of the flow and don't extend it — package changes belong in roles.

**Static checks (the only verification safe for an agent):**

```bash
printf 'x\n' > /tmp/vault-pw
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --syntax-check
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --list-tags
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-inventory --graph
```

Do **not** run `local.yml` for real: it mutates the workstation
(sudoers, systemd services, shell, `~/.config`) and needs an unlocked Bitwarden vault.
There is no CI, no lint config, and no test suite in this repo.

## Vault gotcha (blocks every ansible command)

`ansible.cfg` sets `vault_password_file = scripts/ansible_vault_pass.sh`, which runs
`rbw get ansible-vault-pass`. If `rbw` cannot answer — vault locked, no TTY for
pinentry — *every* command fails, including `--syntax-check`, `--list-tags`, and
`ansible-inventory --graph`. The dummy-password-file override above is the way to work
around it for static checks (a wrong password only fails when a vaulted var is read).

Vault-backed vars in use: `vault_sudo_password` (set as `ansible_become_pass` in
`group_vars/all/all.yml`), plus `gemini_api_key`, `groq_api_key`, `openrouter_api_key`
templated into `~/.zshenv` for nvim's avante plugin. New secret = key added to
`inventories/local/group_vars/all/vault.yml` **and** a matching item in Bitwarden.

## How role selection works

`local.yml` loads `inventories/local/host_vars/{{ ansible_facts['hostname'] }}.yml`
(short hostname, not FQDN) and includes each entry of `enabled_roles`. Those files
just concatenate profiles defined in `inventories/local/group_vars/all/all.yml`
(`base`, `desktop`, `dev`) plus extras.

- Adding a role: put it in a profile in `all.yml`, or directly in a host_vars
  `enabled_roles` list. `roles/waybar/` is currently in no profile — not deployed.
- **Order matters**: `base` ends with `yay`, which creates the `aur_builder` user and
  NOPASSWD pacman rule that `aur_cli_tools` depends on.
- Role names are also tags (`apply: tags: ["{{ role_item }}"]`), so
  `--tags nvim` targets one role. `--list-tags` cannot show them (dynamic include);
  it only reports `always`.
- Host-specific vars must exist per host: `roles/niri/templates/config.kdl.j2` requires
  `niri_output_name`, `niri_output_mode`, `niri_output_scale`, defined only in
  `host_vars/dsk.yml`. A new host that enables `niri` will fail without them.
- `inventories/local/hosts.ini` defines only `localhost`; plays target
  `hosts: localhost, connection: local`. There are no remote hosts.
- Configs deploy to `ansible_facts.user_dir` (home of the user running ansible), so
  never run the playbooks under `sudo` — files would land in `/root`.

## Conventions inside a role

- Static config → `roles/<name>/files/...` symlinked into `~/.config/...` with
  `file: state=link, force=true`. Editing the repo file changes the live config.
- Templating (`templates/*.j2`) only for host-specific values: `niri`, `tuigreet`,
  `zsh/.zshenv`. Everything else is a plain symlink.
- Package installs, two modules by intent:
  - `ansible.builtin.package` (unguarded) when the package name is the same across
    distros — used by `git`, `zsh`, `tmux`, `nvim`, `waybar`. Prefer this for anything
    already in that set.
  - `community.general.pacman` guarded by `when: ansible_facts['pkg_mgr'] == 'pacman'`
    for Arch-specific names, so the play still succeeds on other distros rather than
    failing on an unknown package — used by `alacritty`, `cli_tools`, `fonts`, `gtk`,
    `niri`, `noctalia`, `tuigreet`, `xdg_user_dirs`.
  - AUR packages go through `kewlfft.aur.aur` with `become_user: aur_builder`, and are
    guarded by `ansible_facts['distribution'] == 'Archlinux'` instead of `pkg_mgr`.
- Never inline secrets in `files/` — they are symlinked verbatim into dotfiles;
  route secrets through `vault.yml` into a template (see `zshenv.j2`).
- Match existing YAML style: `---` header, `name:` on every task, 2-space indent,
  `ansible.builtin.` FQCNs.

## nvim subtree

`roles/nvim/files/nvim/` is a vendored LazyVim starter symlinked as `~/.config/nvim`.
`lazy-lock.json` is committed (plugin versions pinned), extras are declared in
`lazyvim.json`, and local changes belong in `lua/plugins/*.lua`
(2-space indent, width 120 per `stylua.toml`). Upstream LazyVim files
(`LICENSE`, `README.md`, `.gitignore`, `example.lua`) are intentionally kept — don't
prune them without asking.