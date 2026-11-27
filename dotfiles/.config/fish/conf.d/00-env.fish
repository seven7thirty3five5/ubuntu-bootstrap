# Sourced by every fish, interactive or not, before config.fish.

# -g (global) keeps PATH out of universal variables, so this file stays the source of truth.
# Comes first because mise's standalone installer (mise.run) puts mise in ~/.local/bin.
fish_add_path -g ~/.local/bin

set -gx EDITOR vim
set -gx VISUAL $EDITOR

# Keep last: PATH entries added after activation would outrank mise's tools.
# Full activation for interactive shells, shims for scripts and IDEs.
if command -q mise
    if status is-interactive
        mise activate fish | source
    else
        mise activate fish --shims | source
    end
end
