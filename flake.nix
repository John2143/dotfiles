{
  inputs = {
    #nixpkgs.url = "github:John2143/nixpkgs/johnpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nix-cachyos-kernel.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    oh-my-pi = {
      url = "github:John2143/oh-my-pi/john";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprcap = {
      url = "github:alonso-herreros/hyprcap";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    waytop = {
      url = "github:vevota/waytop";
      flake = false;
    };

    node-rally-tools = {
      url = "github:John2143/node-rally-tools";
    };

    autoclicker = {
      url = "path:./autoclicker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    screen-control = {
      url = "path:./screen-control";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    voxtype = {
      url = "github:peteonrails/voxtype/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nix-cachyos-kernel,
    agenix,
    waytop,
    voxtype,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    catchy-os = [
      ({pkgs, ...}: {
        nixpkgs.overlays = [
          nix-cachyos-kernel.overlays.default
          #nix-cachyos-kernel.overlays.pinned
        ];
      })
      ({pkgs, ...}: {
        boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
        #hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
      })
    ];
    my-keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOktI2Vry/5fbhZiG35o5mf7w3dnaTEDqkRJVM07cu3a john@arch"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVckq0oXyXkxiLo39typ6PR039XrLwze/Cb0PZaTzmi john@office"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHjc0NNrHCwjrBUvUByFoFPW9vKGVFsWVD6LoKp1FLtNaIjyigMTYXoCKZSNNguKdNwUiyqKIZfCExZmgc3Cccw= phone"
    ];

    # mkHost name modules → { name = <config>; "vm-<name>" = <vm-config>; }
    # Every host defined this way automatically gets a runnable VM variant.
    # Usage: nix run .#nixosConfigurations.vm-<name>.config.system.build.vm
    mkHost = {
      name,
      modules,
    }: let
      base = {
        inherit system;
        specialArgs = {
          inherit inputs;
          compName = name;
          sshKeys = my-keys;
        };
        modules =
          [
            inputs.home-manager.nixosModules.default
            agenix.nixosModules.default
          ]
          ++ modules;
      };
      vmOverride = {
        config,
        lib,
        ...
      }: {
        # Only override GPU drivers if X11/Wayland is enabled
        services.xserver.videoDrivers =
          lib.mkIf config.services.xserver.enable
          (lib.mkForce ["modesetting"]);
        services.tailscale.enable = lib.mkForce false;
        virtualisation.vmVariant = {
          virtualisation = {
            memorySize = 8192;
            cores = 4;
            graphics = true;
            resolution = {
              x = 1920;
              y = 1080;
            };
          };
          users.users.john.initialPassword = "john";
        };
      };
    in {
      ${name} = nixpkgs.lib.nixosSystem base;
      "vm-${name}" = nixpkgs.lib.nixosSystem (base
        // {
          specialArgs = base.specialArgs // {compName = "vm-${name}";};
          modules = base.modules ++ [vmOverride];
        });
    };
  in rec {
    formatter.x86_64-linux = nixpkgs.legacyPackages.${system}.alejandra;
    formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;

    nixosConfigurations =
      (mkHost {
        name = "office";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/shared-games-configuration.nix
          ./nixos/office-configuration.nix
          ./nixos/firejail-desktop.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/modules/restic-backup.nix
          ./nixos/modules/nas-mounts.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix

          ./nixos/modules/waybar-popup.nix
        ];
      })
      // (mkHost {
        name = "arch";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/shared-games-configuration.nix
          ./nixos/arch-configuration.nix
          ./nixos/firejail-desktop.nix
          ./nixos/modules/k3s-server.nix
          ./nixos/modules/restic-backup.nix
          ./nixos/modules/nas-mounts.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix
          ./nixos/modules/waybar-popup.nix
        ];
      })
      // (mkHost {
        name = "closet";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/closet-configuration.nix
          ./nixos/modules/k3s-server.nix
          ./nixos/modules/longhorn-host.nix
          ./nixos/modules/restic-backup.nix
          ./nixos/modules/nas-mounts.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix
        ];
      })
      // (mkHost {
        name = "pite";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/remote-cli-config.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix
          ./nixos/modules/remote-builders.nix
          ./nixos/pite-canary.nix
        ];
      })
      // (mkHost {
        name = "aman";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/remote-cli-config.nix
          ./nixos/tailscale.nix
          ./nixos/modules/mullvad.nix

          ./nixos/modules/attic.nix

          ({...}: {
            services.avahi = {
              reflector = true;
              allowInterfaces = ["end0" "wlan0"];
            };
          })
        ];
      })
      // (mkHost {
        name = "vpin";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/remote-cli-config.nix
          ./nixos/tailscale.nix
          ./nixos/modules/mullvad.nix

          ./nixos/modules/attic.nix
          ./nixos/modules/remote-builders.nix
        ];
      })
      // (mkHost {
        name = "term";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/security-configuration.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix
        ];
      })
      // (mkHost {
        name = "secu";
        modules = [
          inputs.disko.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/shared-configuration.nix
          ./nixos/secu-configuration.nix
          ./nixos/modules/disko_secu.nix
          ./nixos/modules/restic-backup.nix
          ./nixos/modules/nas-mounts.nix
          ./nixos/tailscale.nix
          ## POST-INSTALL: uncomment after TPM enrollment ##
          ./nixos/modules/secu-post-install.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix
        ];
      })
      // (mkHost {
        name = "nas";
        modules = [
          inputs.disko.nixosModules.default
          ./nixos/shared-cli-configuration.nix
          ./nixos/nas-configuration.nix
          ./nixos/modules/k3s-server.nix
          ./nixos/modules/disko_nas.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix
        ];
      })
      // (mkHost {
        name = "big";
        modules = [
          ./nixos/shared-cli-configuration.nix
          ./nixos/big-configuration.nix
          ./nixos/modules/k3s-agent.nix
          ./nixos/modules/restic-backup.nix
          ./nixos/tailscale.nix

          ./nixos/modules/attic.nix

          ./nixos/modules/remote-builders.nix
        ];
      })
      // {
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
            compName = "installer";
            sshKeys = my-keys;
          };
          modules = [
            inputs.home-manager.nixosModules.default
            agenix.nixosModules.default
            ./nixos/shared-cli-configuration.nix
            ./nixos/modules/user-john.nix
            ({modulesPath, ...}: {
              imports = [
                (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
              ];
              home-manager.users."john" = import ./nixos/home-cli.nix;
              users.users."john".openssh.authorizedKeys.keys = my-keys;
            })
          ];
        };
      };

    packages.x86_64-linux.installer = nixosConfigurations.installer.config.system.build.isoImage;
    packages.x86_64-linux.waytop = nixpkgs.legacyPackages.x86_64-linux.callPackage ./nixos/waytop.nix {
      src = waytop;
    };
    packages.x86_64-linux.frigate-genai-genai-image = nixosConfigurations.arch.config.system.build.frigateGenaiGenaiImage;
    packages.x86_64-linux.frigate-genai-ffmpeg-image = nixosConfigurations.arch.config.system.build.frigateGenaiFfmpegImage;

    darwinConfigurations.mac = inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        compName = "mac";
        sshKeys = my-keys;
      };
      modules = [
        inputs.home-manager.darwinModules.default
        agenix.darwinModules.default
        ./nixos/darwin-configuration.nix
      ];
    };
  };
}
