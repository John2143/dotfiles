# DESCRIPTION: Select a Tailscale exit node
set -f nodes (tailscale status --json | jq -r '.Peer[] | select(.ExitNodeOption == true) | .DNSName' | string collect)
# add a node of "None" to the list of nodes so that we can exit if the user doesn't select a node
# and also keep newlines separating the nodes so that fzf can display them on separate lines
set nodes "None"\n"$nodes"
set -f new_node (echo $nodes | fzf)
if test "A$new_node" = "A"
    exit 1
end
if test $new_node = "None"
    sudo tailscale set --exit-node=""
else
    sudo tailscale set --exit-node=$new_node --exit-node-allow-lan-access
end
