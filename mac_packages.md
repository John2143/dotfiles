# Mac System State (2026-05-12)

## System Info

- Architecture: arm64 (Apple Silicon)
- OS: macOS 15.7.5 (Build 24G624)
- Nix: 2.22.1 (standalone, no nix-darwin)
- Default shell: /bin/zsh
- Fish: 4.1.2 (installed via brew)
- Node: v25.2.1 (via fnm)
- Go: 1.25.2
- Python: 3.14.2

## Homebrew Taps

```
aljohri/-
cfergeau/crc
danielgtaylor/restish
probe-rs/probe-rs
sergiobenitez/osxct
tsub/s3-edit
```

## Formulae (directly installed)

These are the explicitly installed formulae (not transitive dependencies):

```
act
argo
argocd
asciinema
autocannon
awscli
bacon
bat
bpytop
choose-rust
cloc
cmake
dasel
dfu-util
dive
docker
dust
eksctl
eza
fd
ffmpeg
fish
fnm
fzf
gcc
gh
gimme-aws-creds
git
git-delta
gnupg
go
gopls
graphviz
gstreamer
harfbuzz
helm
htop
icu4c@76
istioctl
jq
k8sgpt
k9s
kind
kubernetes-cli
lazygit
libmediainfo
libplacebo
make
media-info
minikube
mono
mpv
ncdu
neovim
ninja
nmap
p7zip
pkgconf
pnpm
postgresql@14
protobuf
python-setuptools
python@3.8
python@3.11
ripgrep
s3cmd
skopeo
spdx-sbom-generator
starship
stlink
temporal
terraform
tesseract
tflint
tmux
tox
tree-sitter
virtualenv
websocat
x86_64-linux-gnu-binutils
xq
yq
aljohri/-/docx2pdf
cfergeau/crc/vfkit
probe-rs/probe-rs/probe-rs
sergiobenitez/osxct/x86_64-unknown-linux-gnu
tsub/s3-edit/s3-edit
```

## Casks (GUI apps)

```
bruno
cmake-app
gstreamer-development
gstreamer-runtime
insomnia
keycastr
krita
lens
mongodb-compass
obs
pgadmin4
plex
sage
vlc
warp
```

## Go tools (installed via brew bundle)

```
goa.design/goa/v3/cmd/goa
github.com/golangci/golangci-lint/cmd/golangci-lint
github.com/pressly/goose/v3/cmd/goose
github.com/Songmu/make2help/cmd/make2help
github.com/goware/modvendor
montage-cli
github.com/matryer/moq
github.com/sqlc-dev/sqlc/cmd/sqlc
```

## VS Code extensions

```
anysphere.remote-ssh
```

## Notable dependencies (transitive, but worth noting)

These are pulled in as dependencies but are relevant for the nix migration since
some workloads depend on them being available:

- gstreamer (+ gtk3, gtk4, vulkan stack)
- tesseract (OCR, pulled in by ffmpeg)
- postgresql@14
- tree-sitter (neovim dependency)
- luajit (neovim dependency)
- python@3.8, python@3.11, python@3.12, python@3.13, python@3.14

## Niche / cross-compilation packages

These may not have direct nixpkgs equivalents and need special handling:

- `probe-rs` — embedded ARM debugger/flasher (from tap probe-rs/probe-rs)
- `stlink` — STM32 programmer
- `dfu-util` — USB DFU firmware flasher
- `x86_64-linux-gnu-binutils` — cross-compilation toolchain
- `x86_64-unknown-linux-gnu` — cross-compilation toolchain (from tap sergiobenitez/osxct)
- `gimme-aws-creds` — Okta-based AWS credential helper
- `vfkit` — macOS virtualization framework CLI (from tap cfergeau/crc)
- `docx2pdf` — Word to PDF converter (from tap aljohri/-)

## Migration notes

- Default shell is zsh but fish 4.1.2 is the working shell (set via brew)
- fnm manages Node versions — nix can replace this or coexist
- Many formulae are transitive deps of ffmpeg/mpv/gstreamer — in nix these come automatically
- Go tools should be managed via `go install` or nix overlays, not system packages
- Kubernetes tools (helm, kubectl, k9s, kind, minikube, istioctl, argocd, eksctl) are a cluster — all available in nixpkgs
- The cross-compilation toolchain (x86_64-linux-gnu) is used for embedded/Rust cross-builds
