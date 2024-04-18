function mullvad-split-tunnel --description 'Add split-tunneling for a single application'
    set appname "$argv[1]";
    set procs (ps aux | grep $appname | grep -v "0:00 rg" | choose 1)
    set num_procs (echo $procs | wc -l)

    # Echo to stderr so that other scripts can use this command
    echo 1>&2 "Ignoring $appname ($num_procs matches)";
    for pid in $procs;
        echo -n "Split-tunneling $pid ... ";
        mullvad split-tunnel add $pid;
    end
    echo 1>&2 "Done"
end

function __get_program_names
    ps aux | choose 10 | sort | uniq
end

complete -r -c mullvad-split-tunnel -a "(__get_program_names)"
