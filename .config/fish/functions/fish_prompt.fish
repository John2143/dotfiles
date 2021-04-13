# Defined in /var/folders/w4/v2kb4w2n6_gb8n05jk8z8v6jhlc_9c/T//fish.tYKLpd/fish_prompt.fish @ line 2
function fish_prompt --description 'Informative prompt'
    #Save the return status of the previous command
    set -l last_pipestatus $pipestatus
    set -g __fish_git_prompt_showupstream auto
    set -g __fish_git_prompt_showuntrackedfiles true
    set -g __fish_git_prompt_showdirtystate true
    set -g __fish_git_prompt_show_informative_status true

    switch "$USER"
        case root toor
            printf '%s@%s %s%s%s# ' $USER (prompt_hostname) (set -q fish_color_cwd_root
                                                             and set_color $fish_color_cwd_root
                                                             or set_color $fish_color_cwd) \
                (prompt_pwd) (set_color normal)
        case '*'
            set -l pipestatus_string (__fish_print_pipestatus "[" "] " "|" (set_color $fish_color_status) \
                                      (set_color --bold $fish_color_status) $last_pipestatus)

            printf '\n[%s] %s%s%s@%s%s %s%s%s%s %s %s%s \f\r$ ' (date "+%H:%M %p") (set_color brwhite) \
                $USER (set_color black) (set_color white) (prompt_hostname) \
                (set_color $fish_color_cwd) (dirs) (set_color white) (fish_git_prompt) $pipestatus_string \
                (set_color green)
    end

    if set -q VIRTUAL_ENV
        echo -n -s (set_color -b blue white) "(" (basename "$VIRTUAL_ENV") ")" (set_color normal) " "
    end
end
