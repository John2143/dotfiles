# DESCRIPTION: Run iperf3 client against a server. Usage: iperf-cli <host> [-- IPERF3_ARGS...]

set -l host $argv[1]

if test -z "$host"; or test "$host" = "-h"; or test "$host" = "--help"
	echo "Usage: iperf-cli <host> [-- IPERF3_ARGS...]"
	echo ""
	echo "Connects to an iperf3 server at <host> with 4 parallel streams."
	echo "Default: 10-second test with 4 parallel streams."
	echo "Pass extra iperf3 args after --, e.g.: iperf-cli nas.local -- -t 30 -P 8"
	return 0
end

set -l iperf_argv $argv[2..-1]

nix run nixpkgs#iperf3 -- -c $host -t 10 -P 4 $iperf_argv
