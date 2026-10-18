# AGENTS.md

Ansible-managed dotfiles for a personal Arch Linux workstation, plus the Ubuntu
server that runs the homelab container stacks. One role per tool; configs live in
the repo and are symlinked into `~/.config`.

## Commands

```bash
ansible-galaxy collection install -r requirements.yml   # once; kewlfft.aur, community.docker
ansible-playbook local.yml                              # apply everything this host enables
ansible-playbook homelab.yml                            # apply everything srv enables
```

`local.yml` and `homelab.yml` are the only entrypoints, one per inventory.
`setup.yml` was removed (commit `7480559`) — it predated the role structure and
duplicated what roles install. Package changes belong in roles.

**Static checks (safe for an agent):**

```bash
printf 'x\n' > /tmp/vault-pw
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --syntax-check
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook homelab.yml --syntax-check
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml --list-tags
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-inventory --graph
```

`--syntax-check` does **not** catch a missing role: the `include_role` on
`machine_profile` is dynamic, so a `machine_profile` pointing at a role that does not
exist still passes. The noop sandbox below is what actually proves the graph.

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
for d in ('base', 'gui', 'desktop', 'dev', 'dsk', 'arch-distrobox', 'srv', 'srv_services'):
    p = pathlib.Path('roles') / d / 'tasks' / 'main.yml'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f'---\n- name: {d}\n  tags: [{d}]\n  block:\n'
                 f'    - name: noop\n      ansible.builtin.debug: msg=noop-{d}\n')
pathlib.Path('inventories/local/group_vars/all/vault.yml').unlink()
EOF
printf 'ansible_become_pass: dummy\n' > inventories/local/group_vars/all/all.yml
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook local.yml
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook homelab.yml
ANSIBLE_VAULT_PASSWORD_FILE=/tmp/vault-pw ansible-playbook homelab.yml --tags immich
```

Real roles still need a `tasks/main.yml` to appear in the trace — a role with only a
`meta/main.yml` is invisible in the output, which is confusing when checking a group.
Add a noop for those too (`base`, `gui`, `desktop`, `dev`, `dsk`, `arch-distrobox`,
`srv`, `srv_services`). Always `rm -rf /tmp/sbx` and the dummy vault file afterwards.

Deleting `inventories/local/group_vars/all/vault.yml` is enough to break the vault for
both inventories: `inventories/homelab/group_vars/all/vault.yml` is a symlink to it, so
it dangles.

Do **not** run `local.yml` or `homelab.yml` against the real repo: they mutate the
workstation and the server (sudoers, systemd services, shell, `~/.config`, container
stacks, snapper) and need an unlocked Bitwarden vault. There is no CI, no lint config,
and no test suite in this repo.

## Vault gotcha (blocks every ansible command)

`ansible.cfg` sets `vault_password_file = scripts/ansible_vault_pass.sh`, which runs
`rbw get ansible-vault-pass`. If `rbw` cannot answer — vault locked, no TTY for
pinentry — *every* command fails, including `--syntax-check`, `--list-tags`, and
`ansible-inventory --graph`. The dummy-password-file override above is the way to work
around it for static checks (a wrong password only fails when a vaulted var is read).

Vault-backed vars in use:

- `vault_sudo_password` — set as `ansible_become_pass` in `group_vars/all/all.yml`,
  so it applies to both inventories.
- `gemini_api_key`, `groq_api_key`, `openrouter_api_key` — templated into
  `~/.zshenv` for nvim's avante plugin.
- `immich_db_password` — `roles/immich/templates/env.j2`.
- `samba_user`, `samba_password` — `roles/samba/templates/env.j2`.
- `webdav_user`, `webdav_password` — `roles/rclone-webdav/templates/env.j2`.

New secret = key added to `inventories/local/group_vars/all/vault.yml` **and** a
matching item in Bitwarden. Add it there and not in `inventories/homelab/...`: that
path is a symlink to the same file.

### The homelab vault symlink

`inventories/homelab/group_vars/all/{all.yml,vault.yml}` are symlinks to
`inventories/local/group_vars/all/`. Ansible reads group_vars relative to the
inventory source, so without the symlinks the server would have no
`ansible_become_pass` and no secrets at all. There is exactly one vault file to edit.
Git records these as mode `120000`; do not "fix" them into real files.

If you ever see `Decryption failed (no vault secrets were found that could decrypt)`
during a static check, that is the dummy password, not a broken symlink — a broken
symlink reports a missing file instead.

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

### The two inventories

`ansible.cfg` sets `inventory = inventories/local/,inventories/homelab/`, so both are
always loaded and `local.yml` and `homelab.yml` pick their hosts out of them:

| Inventory | Playbook | `hosts:` | Profiles |
| --- | --- | --- | --- |
| `inventories/local/` | `local.yml` | `localhost` (connection: local) | `dsk`, `arch-distrobox` |
| `inventories/homelab/` | `homelab.yml` | `homelab` (connection: ssh) | `srv` |

The two inventories resolve `machine_profile` differently, and the difference matters:

- `local.yml` needs a `pre_tasks` block with `include_vars` pointing at
  `inventories/local/host_vars/{{ ansible_facts['hostname'] }}.yml`. It has to, because
  the filename is the running machine's hostname, which is not known until facts are
  gathered.
- `homelab.yml` has no pre_tasks. `inventories/homelab/host_vars/srv.yml` is a plain
  inventory-adjacent `host_vars/` directory, so Ansible loads it natively. Do not copy
  the `include_vars` trick across — it would work by accident and hide the real path.

`localhost` sits in `@ungrouped`, not in a group, because `hosts.ini` has no group
header for it. `local.yml` targets it by name.

### Role kinds

A role is **either** a leaf with `tasks/main.yml` that does work **or** a meta-only
groupper with `meta/main.yml` and no `tasks/main.yml`. Groups (`base`, `gui`,
`desktop`, `dev`, `srv_services`) and per-machine roles (`dsk`, `arch-distrobox`, `srv`)
are meta-only.

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
dev     → base, nvim, tmux, herdr
srv_services → docker, storage, immich, nextcloud, servarr, samba, ums, rclone-webdav
dsk           → desktop, dev
arch-distrobox → gui, dev
srv           → base, dev, srv_services
```

`base` and `dev` are shared by both machines. That is the whole point of `srv`:
the server gets the same shell toolchain as the workstation and nothing from `gui` or
`desktop`. `yay` and `herdr` are Arch-only leaves that `base`/`dev` still pull in;
on Ubuntu every task in them is guarded and reports as a no-op. `herdr`'s config is
still symlinked on the server even though no binary is installed there — deliberate,
not an oversight.

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
- Tags are per-playbook in practice: `--tags nvim` works on both `local.yml` and
  `homelab.yml`, but `--tags immich` only does anything under `homelab.yml`. Tags
  are global across inventories, not scoped to one.

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
  `hosts: localhost, connection: local`.
- `inventories/homelab/host_vars/srv.yml` defines the `srv_*` vars every stack and the
  `storage` role needs: `srv_puid`, `srv_pgid`, `srv_timezone`, `srv_container_root`,
  `srv_media_root`, `srv_storage_subvolume`. A second server profile must define all of
  them or its stacks fail on undefined variables.
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
  - `ansible.builtin.apt` guarded by `when: ansible_facts['pkg_mgr'] == 'apt'` for the
    Debian/Ubuntu half of a role that has to run on both. `srv` reaches `base` and `dev`
    on Ubuntu, so `cli_tools` and `xdg_user_dirs` each carry both branches. Name
    differences are handled by listing the apt name, not by relying on resolution:
    `fd` → `fd-find`, `rust` → `rustc`. `cli_tools` also links `/usr/local/bin/fd` →
    `/usr/bin/fdfind` so the rename does not break muscle memory or nvim plugins.
  - Adding a new apt source needs a forced cache refresh: `update_cache: true` with a
    `cache_valid_time` can leave the cache stale and the new package unfindable. That
    is why the yazi repo block in `cli_tools` uses `cache_valid_time: 0`.
  - AUR packages go through `kewlfft.aur.aur` with `become_user: aur_builder`, and are
    guarded by `ansible_facts['distribution'] == 'Archlinux'` instead of `pkg_mgr`.
    Only the AUR task carries the `aur` tag; the rest of the role is distro-agnostic
    and runs everywhere. `cli_tools`, `yay`, and `herdr` use this today. Adding a new
    AUR package means adding it to the existing `loop:` in `cli_tools/tasks/main.yml` —
    do **not** spin up a new role for it. Split it out only if the AUR packages stop
    being CLI tools. A role that only installs one AUR package does not need a `yay`
    meta dependency either: on the paths that reach it, `cli_tools` has already run
    `yay` (`dev → base → cli_tools → yay`).
- Never inline secrets in `files/` — they are symlinked verbatim into dotfiles;
  route secrets through `vault.yml` into a template (see `zshenv.j2`).
- Match existing YAML style: `---` header, `name:` on every task, 2-space indent,
  `ansible.builtin.` FQCNs.

## Container stacks

The eight `srv_services` leaves under `roles/` (`immich`, `nextcloud`, `servarr`,
`samba`, `ums`, `rclone-webdav`, plus `docker` and `storage`) follow one shape, and a
new stack should copy an existing one rather than invent a layout:

```
roles/<stack>/tasks/main.yml            # dirs -> .env -> compose file -> compose up
roles/<stack>/files/docker-compose.yml  # static, symlink-free
roles/<stack>/templates/env.j2          # the only templated file
```

**The split that makes this work:** the compose file is static and carries **no** host
paths, **no** credentials and **no** `${...}` that is not defined in `env.j2`. Compose
reads the `.env` sitting next to the compose file automatically and interpolates
`${VAR}` from it — including inside `command:`. So a secret only ever has to be
rendered once, into a mode `0600` file on the host.

- `.env` carries: host paths (`srv_container_root`, `srv_media_root`,
  `srv_storage_subvolume`), container identity (`srv_puid`, `srv_pgid`, `srv_timezone`),
  and secrets from the vault.
- `.env` does **not** carry published ports. Those stay literal in the compose file —
  there are 14 of them in `servarr` alone and none is a secret.
- The compose file is `copy`, never `symlink`: it lands under `/srv/container/`, not
  `~/.config`, and it must not be a symlink into the repo on the server. This is the
  one deliberate departure from the symlink convention above.
- Secrets are referenced **without** a `| default('')`. A missing vault key must fail
  the play loudly, not start a container with a blank password.
- Every stack ends with `community.docker.docker_compose_v2`, `state: present`,
  `pull: policy`, `remove_orphans: true`, `wait: true`, `wait_timeout: 600`. Keep these
  identical across stacks; they are what make a re-run idempotent. `pull: policy` pulls
  only what is missing, so re-runs do not fight `:latest` tags.
- The role must `file: state=directory` the stack's own project dir before templating
  into it. `template` does not create parent directories. This bit `servarr` once.

### Things that will bite you

- `rclone-webdav` takes its credentials as command line flags only, so the password is
  visible in `docker inspect` output on the host. Unavoidable without replacing the
  webdav server; acceptable because it is no longer in git, and anyone who can inspect
  the container can already read the `.env`.
- `dperson/samba` splits `-u` and `-s` on `;`, so `samba_user` / `samba_password` must
  not contain `;` or `"`. This is noted in that role's `env.j2`.
- The `:z` volume suffix is SELinux relabelling. Harmless under Ubuntu's AppArmor, kept
  from the original compose files.
- `immich`'s `DB_PASSWORD` is interpolated straight into postgres, so restrict it to
  `A-Za-z0-9`.
- `storage` assumes `srv_storage_subvolume` is **already mounted**. It verifies the
  filesystem type with `findmnt` and asserts btrfs rather than creating anything.
  Formatting a disk is never an Ansible task here.
- The server was reinstalled from Fedora IoT (immutable, and `/var/home/alfrest`) to
  Ubuntu Server 24.04. Old compose files used `/var/home/alfrest/container/...`, which
  does not exist on Ubuntu; that is now `srv_container_root: /srv/container`. Migrating
  existing app data means moving those directories once, by hand.

## nvim subtree

`roles/nvim/files/nvim/` is a vendored LazyVim starter symlinked as `~/.config/nvim`.
`lazy-lock.json` is committed (plugin versions pinned), extras are declared in
`lazyvim.json`, and local changes belong in `lua/plugins/*.lua`
(2-space indent, width 120 per `stylua.toml`). Upstream LazyVim files
(`LICENSE`, `README.md`, `.gitignore`, `example.lua`) are intentionally kept — don't
prune them without asking.