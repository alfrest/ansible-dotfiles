# AGENTS.md

Ansible-managed dotfiles for a personal Arch Linux machine. One role per tool;
configs live in the repo and are symlinked into `~/.config`.

## Commands

```bash
ansible-galaxy collection install -r requirements.yml   # once; installs kewlfft.aur
ansible-playbook local.yml                              # apply everything this host enables
```

`local.yml` is the only entrypoint. `setup.yml` was removed (commit `7480559`) — it
predated the role structure and duplicated what roles install. Package changes belong
in roles.

**Static checks (safe for an agent):**

```bash
printf 'x\n' > /tmp/vault-pw
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --syntax-check
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --list-tags
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-inventory --graph
```

**Noop sandbox — to check the dependency graph or tag behaviour without mutating
anything.** Copy the repo to `/tmp`, swap every task file for a debug noop, drop the
vault file, then run for real:

```bash
rm -rf /tmp/sbx && cp -r . /tmp/sbx && cd /tmp/sbx
python3 - <<'EOF'
import pathlib
for f in sorted(pathlib.Path('roles').glob('*/tasks/main.yml')):
    r = f.parts[1]
    f.write_text(f'---\n- name: {r}\n  tags: [{r}]\n  block:\n'
                 f'    - name: noop\n      ansible.builtin.debug: msg=noop-{r}\n')
pathlib.Path('inventories/local/group_vars/all/vault.yml').unlink()
EOF
printf 'ansible_become_pass: dummy\n' > inventories/local/group_vars/all/all.yml
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --tags niri
```

Real roles still need a `tasks/main.yml` to appear in the trace — a role with only a
`meta/main.yml` is invisible in the output, which is confusing when checking a group.
Add a noop for those too (`base`, `gui`, `desktop`, `dev`, `dsk`, `arch-distrobox`).
Always `rm -rf /tmp/sbx` and the dummy vault file afterwards.

Do **not** run `local.yml` against the real repo: it mutates the workstation
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
(short hostname, not FQDN) and does a **single** `include_role` on
`machine_profile` — no loop. Each host_vars file points at one meta role:

```yaml
machine_profile: dsk             # host_vars/dsk.yml
machine_profile: arch-distrobox  # host_vars/arch-distrobox.yml
```

That per-machine role is meta-only and lists the groups it wants; the groups pull in
the leaf roles. Nothing else names a role — adding a role means adding it to some
`meta/main.yml`, not editing an inventory list.

### Role kinds

A role is **either** a leaf with `tasks/main.yml` that does work **or** a meta-only
groupper with `meta/main.yml` and no `tasks/main.yml`. Groups (`base`, `gui`,
`desktop`, `dev`) and per-machine roles (`dsk`, `arch-distrobox`) are meta-only.

- Adding a role: write `roles/<name>/tasks/main.yml`, then reference it from a
  group's `meta/main.yml`.
- `roles/waybar/` is the one exception — it has both, because it is in no group and
  therefore not deployed anywhere. Its meta entries document what it *would* need.
- A role that is only ever a dependency can drop its `tasks/main.yml` entirely, but
  then it will not show up in play output or noop-sandbox traces. Keep a noop-ish
  task file if you need to see it.

### The graph

Groups, from `roles/<group>/meta/main.yml`:

```
base    → xdg_user_dirs, cli_tools, git, zsh
gui     → base, fonts, alacritty
desktop → gui, gtk, tuigreet, niri, noctalia
dev     → base, nvim, tmux
dsk           → desktop, dev
arch-distrobox → gui, dev
```

Leaf-to-leaf edges exist where one role's code actually references another:

```
zsh → git            ansible.builtin.git clones oh-my-zsh
alacritty → git      ansible.builtin.git clones alacritty-theme
cli_tools → yay      use: yay + become_user: aur_builder need the sudoers rule
                     yay creates; yay also installs base-devel for makepkg
niri → noctalia      spawn-sh-at-startup "noctalia" plus every noctalia msg hotkey
noctalia → fonts     config.toml sets font_family = "Inter"
tuigreet → niri      pam_gnome_keyring.so, from gnome-keyring which niri installs
waybar → niri, fonts config.jsonc uses niri/workspaces; style.css sets JetBrainsMono
```

Execution order comes from this graph, not from list order. `yay` therefore always
runs before `cli_tools`, and `noctalia` before `niri`.

`yay` is deliberately **not** listed in `base` any more. It used to be, alongside the
separate `aur_cli_tools` role. Both are gone: repo packages and AUR packages are both
installed by `cli_tools`, and `base-devel` moved into `yay` so the build toolchain is
in place before anything tries to build. Listing `yay` twice (once under `base`, once
under `cli_tools`) would be redundant but not wrong — just don't reintroduce the split.

### Tags

Each role tags its own tasks — a `- name: <role>` / `tags: [<role>]` / `block:`
wrapper at the top of `tasks/main.yml`. So `--tags nvim` targets one role.

- `--list-tags` reports only `always`. The `include_role` is dynamic, so role tags
  cannot be enumerated statically. This is inherent, not fixable without replacing
  the dynamic include.
- `--tags <group>` and `--tags <machine>` run nothing: those roles are meta-only.
  Tag a leaf role instead.
- A role that is not part of this host's graph cannot be run by tag at all.

### Gotchas, verified by test

- `when:` on a role gates **every** role in its dependency chain, not just the role
  it is attached to. Verified three levels deep: with the condition false, leaf and
  grandleaf roles all report `skipping`. This is why a static `roles:` list gated on
  `when` does work for per-host selection — but it also means `when` is not a
  per-role opt-out.
- `role:` cannot be templated in a static `roles:` list. `role: "{{ some_var }}"`
  fails with `'ansible_facts' is undefined`; the name must be written out. This is
  the main reason the dynamic `include_role` on `machine_profile` exists instead.
- Tag inheritance through meta dependencies differs between the two forms. A static
  `roles:` list gives a dependency the parent's tag (`desktop : noop TAGS: [desktop,
  gui]`), so `--tags dsk` pulls the whole machine. The dynamic include does not,
  so `--tags dsk` runs nothing.

### Host-specific vars

- `roles/niri/templates/config.kdl.j2` requires `niri_output_name`,
  `niri_output_mode`, `niri_output_scale`, defined only in `host_vars/dsk.yml`. A new
  host whose profile reaches `niri` will fail without them.
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
    Only `cli_tools` and `yay` use this today. Adding a new AUR package means adding it
    to the existing `loop:` in `cli_tools/tasks/main.yml` — do **not** spin up a new
    role for it. Split it out only if the AUR packages stop being CLI tools.
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