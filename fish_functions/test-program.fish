# DESCRIPTION: Scaffold and build a new Rust flake project
set -f program "$argv[1]"
mkdir -p ~/test/$program
cd ~/test/$program
nix flake init --template templates#rust
nix-shell -p cargo --command "cargo init . --bin --name $program"
nix-shell -p cargo --command "cargo b"
echo "/result" >> .gitignore
echo ".direnv" >> .gitignore
git add -A
nix build .
./result/bin/$program
direnv allow
git add -A
git commit -m "Initial commit"
