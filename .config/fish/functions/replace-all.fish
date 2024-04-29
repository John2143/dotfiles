function replace-all --description 'Replace all of a string in files in subdirectories'
    set -f find $argv[1]
    set -f rep $argv[2]
    set -f filter $argv[3]
    if test $filter
        echo "Replacing /$find/ with /$rep/ with extra $filter"
        rg --files-with-matches $filter | rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
    else
        echo "Replacing /$find/ with /$rep/"
        rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
    end

end

