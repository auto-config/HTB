# Bashrc Changes for HTB Workflow

This document tracks the `.bashrc` additions used with this repository.

## Purpose

- Add a `box` helper to jump into a machine workspace.
- Automatically load that box's `.env` values (`target`, `ports`, `LHOST`, etc.).
- Enable tab-completion for existing box directories.

## Code Added to `.bashrc`

```bash
# HTB Custom

box() {
    cd ~/Desktop/HTB/"$1" || return
    source .env
}

_box_complete() {
    COMPREPLY=( $(compgen -W "$(ls ~/Desktop/HTB)" -- "${COMP_WORDS[1]}") )
}

complete -F _box_complete box
```

## Usage

```bash
box <box_name>
```

Example:

```bash
box lame
```

This changes directory to `~/Desktop/HTB/lame` and loads environment variables from `.env`.

## Notes

- `htb-init` creates the `.env` file consumed by `box`.
- Reload shell config after editing `.bashrc`:

```bash
source ~/.bashrc
```
