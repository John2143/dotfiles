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
      pkgs ? null,
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
      } // lib.optionalAttrs (pkgs != null) { inherit pkgs; };
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
      // (mkHost {
        name = "nas";
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              vips_8_17 = prev.vips_8_17.overrideAttrs (old: {
                buildInputs = old.buildInputs ++ [
                  final.libraw
                  final.libultrahdr
                ];
              });
            })
          ];
        };
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
    packages.x86_64-linux.frigate-genai-genai-image = 
      (import ./nixos/modules/frigate-genai-config.nix { 
        inherit (nixpkgs.legacyPackages.${system}) pkgs lib;
      }).frigateGenaiGenaiImage;
    packages.x86_64-linux.frigate-genai-ffmpeg-image = 
      (import ./nixos/modules/frigate-genai-config.nix { 
        inherit (nixpkgs.legacyPackages.${system}) pkgs lib;
      }).frigateGenaiFfmpegImage;

    packages.x86_64-linux.litellm-configmap =
      let
        inherit (nixpkgs) lib;
        yunwuModels = (import ./nixos/modules/yunwu-models.nix { inherit (nixpkgs) lib; });
        yunwuSection = yunwuModels.toLitellmYaml yunwuModels.models;
        pkgs = nixpkgs.legacyPackages.${system};
        configContent = ''
          general_settings:
            master_key: "os.environ/LITELLM_MASTER_KEY"
            store_model_in_db: true
            store_prompts_in_spend_logs: true
          model_list:
            # Local Ollama (office)
            - model_name: "ollama/huihui_ai/qwen3-vl-abliterated:8b"
              litellm_params:
                model: "ollama/huihui_ai/qwen3-vl-abliterated:8b"
                api_base: "http://office.ts.2143.me:11434"
            - model_name: "ollama/*"
              litellm_params:
                model: "ollama/*"
                api_base: "http://office.ts.2143.me:11434"
            # Google Gemini
            - model_name: "gemini/*"
              litellm_params:
                model: "gemini/*"
                api_key: "os.environ/GEMINI_API_KEY"
            # DeepSeek
            - model_name: "deepseek/*"
              litellm_params:
                model: "deepseek/*"
                api_key: "os.environ/DEEPSEEK_API_KEY"
            # Anthropic (Claude)
            - model_name: "anthropic/*"
              litellm_params:
                model: "anthropic/*"
                api_key: "os.environ/ANTHROPIC_API_KEY"
            # OpenAI
            - model_name: "openai/*"
              litellm_params:
                model: "openai/*"
                api_key: "os.environ/OPENAI_API_KEY"
            # OpenRouter
            - model_name: "openrouter/*"
              litellm_params:
                model: "openrouter/*"
                api_key: "os.environ/OPENROUTER_API_KEY"
            # Yunwu
          ${yunwuSection}
            # Yunwu fast
            - model_name: "yunwu/fast/*"
              litellm_params:
                model: "openai/*"
                api_key: "os.environ/YUNWU_FAST_API_KEY"
                api_base: "https://yunwu.ai/v1"
            # Yunwu Official
            - model_name: "yunwu/official/*"
              litellm_params:
                model: "openai/*"
                api_key: "os.environ/YUNWU_OFFICIAL_API_KEY"
                api_base: "https://yunwu.ai/v1"

          litellm_settings:
            drop_params: true
            set_verbose: false
            cache: true
            cache_params:
              type: redis
              host: litellm-redis
              port: "6379"
        '';
        indent4 = lines:
          lib.concatMapStrings (line: "    ${line}\n") (lib.splitString "\n" lines);
      in
      pkgs.writeText "configmap.yaml" (''
        apiVersion: v1
        kind: ConfigMap
        metadata:
          labels:
            app: litellm
          name: litellm-config
        data:
          config.yaml: |
      '' + indent4 configContent);


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
