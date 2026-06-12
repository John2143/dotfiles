# DESCRIPTION: Start iperf3 server with temporary NixOS firewall hole. Auto-cleaned on exit.
# DESCRIPTION: Usage: iperf-srv [-p PORT] [-- IPERF3_ARGS...]

set -l port 5201
set -l iperf_argv

# Parse arguments
set -l i 1
while test $i -le (count $argv)
	switch $argv[$i]
		case -p --port
			set i (math $i + 1)
			set port $argv[$i]
		case --
			set iperf_argv $argv[(math $i + 1)..-1]
			break
		case -h --help
			echo "Usage: iperf-srv [-p PORT] [-- IPERF3_ARGS...]"
			echo ""
			echo "Opens firewall port, starts iperf3 server, removes rule on exit."
			echo "Default port: 5201"
			return 0
		case '*'
			set iperf_argv $argv[$i..-1]
			break
	end
	set i (math $i + 1)
end

# Insert firewall rule (silently skip if already present)
sudo iptables -C nixos-fw -p tcp --dport $port -j nixos-fw-accept 2>/dev/null
set -l had_rule $status

if test $had_rule -ne 0
	sudo iptables -I nixos-fw -p tcp --dport $port -j nixos-fw-accept
	echo "iperf-srv: opened port $port in firewall"
else
	echo "iperf-srv: port $port already open in firewall"
end

# Run iperf3; when it exits, clean up the firewall rule
nix run nixpkgs#iperf3 -- -s -p $port $iperf_argv
set -l iperf_exit $status

if test $had_rule -ne 0
	sudo iptables -D nixos-fw -p tcp --dport $port -j nixos-fw-accept 2>/dev/null
	echo "iperf-srv: closed port $port in firewall"
end

return $iperf_exit
