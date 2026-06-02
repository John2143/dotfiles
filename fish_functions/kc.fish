# DESCRIPTION: Select a kubectl context via fzf
set -f new_env (kubectl config get-contexts -o name | fzf)
if test "A$new_env" = "A"
    exit 1
end
kubectl config use-context $new_env
