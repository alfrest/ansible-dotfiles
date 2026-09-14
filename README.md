# Ansible dotfiles

# Run
```bash
ansible-playbook setup.yml --limit $(hostname) -K
```

# Structure
```
dot_bootstrap/
├── site.yml
└── roles/
    ├── alacritty/
    │   ├── files/                   # Standard static dotfiles go here
    │   │   └── alacritty.toml
    │   └── tasks/
    │       └── main.yml
    └── system_user/
        ├── templates/               # Dynamic dotfiles with variables go here
        │   └── .zshrc.j2
        └── tasks/
            └── main.yml
```

# Static dotfiles
```yaml
- name: Ensure config directory exists
  ansible.builtin.file:
    path: "{{ ansible_user_dir }}/.config/alacritty"
    state: directory
    mode: '0755'

- name: Deploy Alacritty configuration
  ansible.builtin.copy:
    src: alacritty.toml
    dest: "{{ ansible_user_dir }}/.config/alacritty/alacritty.toml"
    mode: '0644'
```

# Dynamic/Templated dotfiles
```yaml
- name: Deploy dynamic .zshrc
  ansible.builtin.template:
    src: .zshrc.j2
    dest: "{{ ansible_user_dir }}/.zshrc"
    mode: '0644'
```

# Symlinks
```yaml
- name: Symlink Alacritty config to repo
  ansible.builtin.file:
    src: "{{ playbook_dir }}/roles/alacritty/files/alacritty.toml"
    dest: "{{ ansible_user_dir }}/.config/alacritty/alacritty.toml"
    state: link
    force: yes
```
