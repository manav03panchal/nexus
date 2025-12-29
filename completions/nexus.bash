# Bash completion for nexus
# Add to ~/.bashrc or ~/.bash_completion:
#   source /path/to/nexus.bash

_nexus_completions() {
    local cur prev opts commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="run list validate init preflight help"

    # Global options
    global_opts="--help --version"

    # Command-specific options
    run_opts="-n --dry-run -v --verbose -q --quiet -c --config -i --identity -u --user -p --parallel-limit --continue-on-error --format --plain"
    list_opts="-c --config --format --plain"
    validate_opts="-c --config"
    init_opts="-o --output -f --force"
    preflight_opts="-c --config --skip -v --verbose --format --plain"

    # Determine context
    case "${COMP_WORDS[1]}" in
        run)
            if [[ ${cur} == -* ]]; then
                COMPREPLY=( $(compgen -W "${run_opts}" -- ${cur}) )
            else
                # Try to get task names from nexus list if available
                local tasks=$(nexus list --format json 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                if [[ -n "$tasks" ]]; then
                    COMPREPLY=( $(compgen -W "${tasks}" -- ${cur}) )
                fi
            fi
            return 0
            ;;
        list)
            COMPREPLY=( $(compgen -W "${list_opts}" -- ${cur}) )
            return 0
            ;;
        validate)
            COMPREPLY=( $(compgen -W "${validate_opts}" -- ${cur}) )
            return 0
            ;;
        init)
            COMPREPLY=( $(compgen -W "${init_opts}" -- ${cur}) )
            return 0
            ;;
        preflight)
            if [[ ${cur} == -* ]]; then
                COMPREPLY=( $(compgen -W "${preflight_opts}" -- ${cur}) )
            else
                local tasks=$(nexus list --format json 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                if [[ -n "$tasks" ]]; then
                    COMPREPLY=( $(compgen -W "${tasks}" -- ${cur}) )
                fi
            fi
            return 0
            ;;
    esac

    # Complete file paths for --config, --identity, --output
    case "${prev}" in
        -c|--config|-i|--identity|-o|--output)
            COMPREPLY=( $(compgen -f -- ${cur}) )
            return 0
            ;;
        --format)
            COMPREPLY=( $(compgen -W "text json" -- ${cur}) )
            return 0
            ;;
        --skip)
            COMPREPLY=( $(compgen -W "config hosts ssh tasks" -- ${cur}) )
            return 0
            ;;
    esac

    # Top-level completion
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands} ${global_opts}" -- ${cur}) )
        return 0
    fi
}

complete -F _nexus_completions nexus
