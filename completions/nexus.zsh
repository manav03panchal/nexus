#compdef nexus

# Zsh completion for nexus
# Add to ~/.zshrc or place in a directory in $fpath:
#   fpath=(/path/to/completions $fpath)
#   autoload -Uz compinit && compinit

_nexus() {
    local -a commands
    local -a global_opts

    commands=(
        'run:Execute one or more tasks'
        'list:List all defined tasks'
        'validate:Validate nexus.exs configuration'
        'init:Create a template nexus.exs file'
        'preflight:Run pre-flight checks before execution'
        'help:Show help information'
    )

    global_opts=(
        '--help[Show help information]'
        '--version[Show version]'
    )

    _arguments -C \
        $global_opts \
        '1:command:->command' \
        '*::arg:->args'

    case "$state" in
        command)
            _describe -t commands 'nexus commands' commands
            ;;
        args)
            case "${words[1]}" in
                run)
                    _nexus_run
                    ;;
                list)
                    _nexus_list
                    ;;
                validate)
                    _nexus_validate
                    ;;
                init)
                    _nexus_init
                    ;;
                preflight)
                    _nexus_preflight
                    ;;
            esac
            ;;
    esac
}

_nexus_run() {
    local -a opts
    opts=(
        '(-n --dry-run)'{-n,--dry-run}'[Show execution plan without running]'
        '(-v --verbose)'{-v,--verbose}'[Increase output verbosity]'
        '(-q --quiet)'{-q,--quiet}'[Minimal output]'
        '(-c --config)'{-c,--config}'[Path to nexus.exs config file]:file:_files'
        '(-i --identity)'{-i,--identity}'[SSH private key file]:file:_files'
        '(-u --user)'{-u,--user}'[SSH user]:user:'
        '(-p --parallel-limit)'{-p,--parallel-limit}'[Maximum parallel tasks]:number:'
        '--continue-on-error[Continue executing on task failure]'
        '--format[Output format]:format:(text json)'
        '--plain[Disable colors and formatting]'
        '*:task:_nexus_tasks'
    )
    _arguments $opts
}

_nexus_list() {
    local -a opts
    opts=(
        '(-c --config)'{-c,--config}'[Path to nexus.exs config file]:file:_files'
        '--format[Output format]:format:(text json)'
        '--plain[Disable colors and formatting]'
    )
    _arguments $opts
}

_nexus_validate() {
    local -a opts
    opts=(
        '(-c --config)'{-c,--config}'[Path to nexus.exs config file]:file:_files'
    )
    _arguments $opts
}

_nexus_init() {
    local -a opts
    opts=(
        '(-o --output)'{-o,--output}'[Output file path]:file:_files'
        '(-f --force)'{-f,--force}'[Overwrite existing file]'
    )
    _arguments $opts
}

_nexus_preflight() {
    local -a opts
    opts=(
        '(-c --config)'{-c,--config}'[Path to nexus.exs config file]:file:_files'
        '--skip[Checks to skip]:checks:(config hosts ssh tasks)'
        '(-v --verbose)'{-v,--verbose}'[Show detailed check results]'
        '--format[Output format]:format:(text json)'
        '--plain[Disable colors and formatting]'
        '*:task:_nexus_tasks'
    )
    _arguments $opts
}

_nexus_tasks() {
    local -a tasks
    # Try to get tasks from nexus list
    if tasks=(${(f)"$(nexus list --format json 2>/dev/null | grep -o '"name":"[^"]*"' | cut -d'"' -f4)"}); then
        _describe -t tasks 'tasks' tasks
    fi
}

_nexus "$@"
