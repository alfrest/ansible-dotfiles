# Ansible dotfiles

Two machines, one repo:

- **`local.yml`** — the Arch Linux workstation.
- **`homelab.yml`** — `srv`, the Ubuntu Server 24.04 host running the container stacks.

## Setup

### Prerequisites

- Install and setup: git ansible rbw
- File exists: inventories/local/host_vars/\<hostname>
- Run

  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

### Secrets

Every secret lives in one encrypted file. Add the stack keys there as well as in
Bitwarden:

```bash
ansible-vault edit inventories/local/group_vars/all/vault.yml
```

| Key | Used by |
| --- | --- |
| `vault_sudo_password` | `ansible_become_pass` for both inventories |
| `gemini_api_key`, `groq_api_key`, `openrouter_api_key` | `~/.zshenv`, nvim avante |
| `immich_db_password` | immich postgres (`A-Za-z0-9` only) |
| `samba_user`, `samba_password` | the samba share (no `;` or `"`) |
| `webdav_user`, `webdav_password` | the rclone webdav endpoint |

### Run

```bash
ansible-playbook local.yml     # this workstation
ansible-playbook homelab.yml   # the server, over ssh
```

Target one piece of either machine by tagging a leaf role:

```bash
ansible-playbook homelab.yml --tags immich
ansible-playbook homelab.yml --tags docker
```

## Server

The server is described entirely by `inventories/homelab/host_vars/srv.yml`:
`machine_profile: srv` picks the role graph, and the `srv_*` vars set the uid/gid the
containers run as, the timezone, and the three paths the stacks share.

| Path | Contents |
| --- | --- |
| `srv_container_root` (`/srv/container`) | per-stack config and databases |
| `srv_storage_subvolume` (`/mnt/storage`) | snappered btrfs volume: media, immich uploads, nextcloud data |
| `srv_media_root` (`/mnt/servarr`) | the library the `*arr` stack, ums and samba share |

`storage` configures snapper over `srv_storage_subvolume` but never creates or formats
it — the mounts are expected to exist, and the role asserts btrfs before touching
`/etc/snapper`.

Stacks deploy to `{{ srv_container_root }}/<stack>/`, where each holds its rendered
`.env` (mode `0600`) and its `docker-compose.yml`. Neither the repo nor the compose
files contain a credential. `AGENTS.md` documents the layout for adding another one.