if status is-interactive
    set -g fish_greeting

    # Built into fish 4.4+. --color-theme=dark pins Mocha; without it, fish
    # switches to Catppuccin Latte when the terminal background is light.
    fish_config theme choose catppuccin-mocha --color-theme=dark

    # These come from mise, which conf.d/00-env.fish already put on PATH.
    command -q starship; and starship init fish | source
    command -q fzf; and fzf --fish | source
    # After fzf so atuin owns ctrl-r; fzf keeps ctrl-t and alt-c.
    # atuin also binds up-arrow and ? (Atuin AI): --disable-up-arrow / --disable-ai opt out.
    command -q atuin; and atuin init fish | source
    command -q zoxide; and zoxide init fish | source
end
