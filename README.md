# Ansible dotfiles

## Setup

### Prerequisites

- Install and setup: git ansible rbw
- File exists: inventories/local/host_vars/\<hostname>
- Run

  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

### Run

```bash
ansible-playbook local.yml
```
