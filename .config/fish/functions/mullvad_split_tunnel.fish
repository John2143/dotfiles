function mullvad-split-tunnel --description 'Add split-tunneling for a single application'
    set appname "$argv[1]"
    echo "Ignoring $appname";
    ps aux | grep $appname | grep -v "0:00 rg" | choose 1 | xargs -I{} fish -c 'mullvad split-tunnel add {}'
end

function __get_program_names
    ps aux | choose 10 | sort | uniq
end

complete -r -c mullvad-split-tunnel -a "(__get_program_names)"
