# HTB Custom

box() {
    cd ~/Desktop/HTB/"$1" || return
    source .env
}

_box_complete() {
    COMPREPLY=( $(compgen -W "$(ls ~/Desktop/HTB)" -- "${COMP_WORDS[1]}") )
}

complete -F _box_complete box
