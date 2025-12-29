# Fish completion for nexus
# Add to ~/.config/fish/completions/nexus.fish

# Disable file completion by default
complete -c nexus -f

# Helper function to get tasks
function __nexus_tasks
    nexus list --format json 2>/dev/null | string match -r '"name":"[^"]*"' | string replace -r '"name":"([^"]*)"' '$1'
end

# Commands
complete -c nexus -n "__fish_use_subcommand" -a run -d "Execute one or more tasks"
complete -c nexus -n "__fish_use_subcommand" -a list -d "List all defined tasks"
complete -c nexus -n "__fish_use_subcommand" -a validate -d "Validate nexus.exs configuration"
complete -c nexus -n "__fish_use_subcommand" -a init -d "Create a template nexus.exs file"
complete -c nexus -n "__fish_use_subcommand" -a preflight -d "Run pre-flight checks before execution"
complete -c nexus -n "__fish_use_subcommand" -a help -d "Show help information"

# Global options
complete -c nexus -l help -d "Show help information"
complete -c nexus -l version -d "Show version"

# run options
complete -c nexus -n "__fish_seen_subcommand_from run" -s n -l dry-run -d "Show execution plan without running"
complete -c nexus -n "__fish_seen_subcommand_from run" -s v -l verbose -d "Increase output verbosity"
complete -c nexus -n "__fish_seen_subcommand_from run" -s q -l quiet -d "Minimal output"
complete -c nexus -n "__fish_seen_subcommand_from run" -s c -l config -r -F -d "Path to nexus.exs config file"
complete -c nexus -n "__fish_seen_subcommand_from run" -s i -l identity -r -F -d "SSH private key file"
complete -c nexus -n "__fish_seen_subcommand_from run" -s u -l user -r -d "SSH user"
complete -c nexus -n "__fish_seen_subcommand_from run" -s p -l parallel-limit -r -d "Maximum parallel tasks"
complete -c nexus -n "__fish_seen_subcommand_from run" -l continue-on-error -d "Continue executing on task failure"
complete -c nexus -n "__fish_seen_subcommand_from run" -l format -r -a "text json" -d "Output format"
complete -c nexus -n "__fish_seen_subcommand_from run" -l plain -d "Disable colors and formatting"
complete -c nexus -n "__fish_seen_subcommand_from run" -a "(__nexus_tasks)" -d "Task"

# list options
complete -c nexus -n "__fish_seen_subcommand_from list" -s c -l config -r -F -d "Path to nexus.exs config file"
complete -c nexus -n "__fish_seen_subcommand_from list" -l format -r -a "text json" -d "Output format"
complete -c nexus -n "__fish_seen_subcommand_from list" -l plain -d "Disable colors and formatting"

# validate options
complete -c nexus -n "__fish_seen_subcommand_from validate" -s c -l config -r -F -d "Path to nexus.exs config file"

# init options
complete -c nexus -n "__fish_seen_subcommand_from init" -s o -l output -r -F -d "Output file path"
complete -c nexus -n "__fish_seen_subcommand_from init" -s f -l force -d "Overwrite existing file"

# preflight options
complete -c nexus -n "__fish_seen_subcommand_from preflight" -s c -l config -r -F -d "Path to nexus.exs config file"
complete -c nexus -n "__fish_seen_subcommand_from preflight" -l skip -r -a "config hosts ssh tasks" -d "Checks to skip"
complete -c nexus -n "__fish_seen_subcommand_from preflight" -s v -l verbose -d "Show detailed check results"
complete -c nexus -n "__fish_seen_subcommand_from preflight" -l format -r -a "text json" -d "Output format"
complete -c nexus -n "__fish_seen_subcommand_from preflight" -l plain -d "Disable colors and formatting"
complete -c nexus -n "__fish_seen_subcommand_from preflight" -a "(__nexus_tasks)" -d "Task"
