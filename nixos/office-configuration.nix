# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  lib,
  pkgs,
  pkgs-stable,
  inputs,
  ...
}: {
  imports = [
    ./office-hardware-configuration.nix
    ./modules/user-john.nix
    ./modules/ollama.nix
    ./modules/teamspeak.nix
    #./waybar.nix
    # inputs.home-manager.nixosModules.default
  ];
  home-manager.users."john" = import ./home.nix;

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
  fileSystems."/".options = [ "noatime" ];
  services.displayManager.lemurs = {
    enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  networking.hostName = "office"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  #networking.wireless.secretsFile = "/run/secrets/wireless.env";
  #networking.wireless.networks = {
  #jimmys_2G.pskRaw = "ext:PSK_HOME";
  #};

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    # useXkbConfig = true; # use xkb.options in tty.
  };

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  systemd.services.office-bad-cpu = {
    wantedBy = ["multi-user.target"];
    description = "CPU perf core 8 is bad on my office comp";
    script = ''${pkgs.fish}/bin/fish /home/john/bin/office.fish'';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."bad-cpu" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5";
      OnUnitActiveSec = "5";
      Unit = "office-bad-cpu.service";
    };
  };

  # I use this computer to rebuild my NixOS configuration daily.
  systemd.services.rebuild-nixos-boot = {
    wantedBy = ["multi-user.target"];
    description = "Update NixOS configuration fr";
    script = ''${pkgs.fish}/bin/fish -c "update; sudo nixos-rebuild --flake ~/dotfiles boot && git add flake.lock && git commit -m 'Update auto: '(date +%Y-%m-%dT%H:%M:%S) && git push || true"'';
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Environment = "HOME=/home/john";
      # Run from /home/john/dotfiles
      WorkingDirectory = "/home/john/dotfiles";
    };
  };

  systemd.timers."rebuild-nixos-boot" = {
    wantedBy = ["timers.target"];
    timerConfig = {
      Unit = "rebuild-nixos-boot.service";
      # At 2:00 PM every day
      OnCalendar = "*-*-* 14:00:00";
      #Persistent = true;
    };
  };

  custom.k3sNodeTaints = ["seated=true:NoSchedule"];
  custom.backup.enable = true;

  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    #inputs.hyprcap.packages.x86_64-linux.default
    pkgs.voxtype
    #inputs.self.packages.x86_64-linux.waytop
  ];

  services.ollama = {
     package = pkgs.ollama-rocm;
  };

  # LiteLLM proxy container — OpenAI-compatible API routing to all providers.
  # API keys loaded from /run/agenix/llm-runtime-keys (decrypted by agenix).
  # Admin UI at http://office.ts.2143.me:4000/ui
  #
  # === Auth ===
  #
  #   The master_key is read from /run/litellm/master-key, generated on first
  #   start by the create-envfile service.  Add LITELLM_MASTER_KEY to the
  #   agenix file to override with a fixed key.
  #
  # === Database ===
  #
  #   Local Postgres container at /var/lib/litellm/postgres.
  #   Password auto-generated on first start.
  #   Connect at postgresql://litellm:<password>@litellm-postgres:5432/litellm
  #
  # Shared podman network so litellm can reach postgres by container name.
  systemd.services."create-litellm-network" = {
    description = "Create the litellm podman network";
    before = ["podman-litellm.service" "podman-litellm-postgres.service"];
    wantedBy = ["podman-litellm.service" "podman-litellm-postgres.service"];
    requiredBy = ["podman-litellm.service" "podman-litellm-postgres.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network create --ignore litellm-net
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.litellm-postgres = {
    image = "docker.io/postgres:17-alpine";
    volumes = [
      "/var/lib/litellm/postgres:/var/lib/postgresql/data"
      "/var/lib/litellm/postgres-password:/run/secrets/postgres-password:ro"
    ];
    environment = {
      POSTGRES_USER = "litellm";
      POSTGRES_DB = "litellm";
      POSTGRES_PASSWORD_FILE = "/run/secrets/postgres-password";
    };
    extraOptions = [
      "--network=litellm-net"
      "--name=litellm-postgres"
    ];
    # Don't expose Postgres port to the host — only reachable via podman network.
  };

  containers.litellm = {
    image = "ghcr.io/berriai/litellm:main-latest";
    ports = ["4000:4000"];
    volumes = [
      "/var/lib/litellm/config.yaml:/app/config.yaml:ro"
      "/var/lib/litellm/env:/app/env:ro"
    ];
    environment = {
      PROXY_BASE_URL = "http://office.ts.2143.me:4000";
      AUTO_REDIRECT_UI_LOGIN_TO_SSO = "true";
    };
    # DATABASE_URL is in the env file (built by create-litellm-config)
    extraOptions = [
      "--env-file=/var/lib/litellm/env"
      "--network=litellm-net"
    ];
    cmd = ["--config" "/app/config.yaml" "--port" "4000" "--host" "0.0.0.0"];
  };
  };

  # Litellm must start after postgres is healthy.
  systemd.services.podman-litellm = {
    after = ["podman-litellm-postgres.service"];
    requires = ["podman-litellm-postgres.service"];
  };

  # Generate the config.yaml from Nix.
  systemd.tmpfiles.rules = [
    "d /run/litellm 0755 root root -"
    "d /var/lib/litellm 0755 root root -"
    "d /var/lib/litellm/postgres 0700 root root -"
  ];

  systemd.services."create-litellm-config" = {
    description = "Generate LiteLLM config and env file";
    before = ["podman-litellm.service" "podman-litellm-postgres.service"];
    wantedBy = ["podman-litellm.service" "podman-litellm-postgres.service"];
    requiredBy = ["podman-litellm.service" "podman-litellm-postgres.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = let
      yamlFormat = pkgs.formats.yaml {};
      configFile = yamlFormat.generate "litellm-config.yaml" {
        general_settings = {
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };
        model_list = [
          # ── Local Ollama ────────────────────────────────────────────
          {
            model_name = "ollama/qwen3.6";
            litellm_params = {
              model = "ollama/qwen3.6";
              api_base = "http://localhost:11434";
            };
          }
          {
            model_name = "ollama/qwen3-vl";
            litellm_params = {
              model = "ollama/qwen3-vl";
              api_base = "http://localhost:11434";
            };
          }
          {
            model_name = "ollama/*";
            litellm_params = {
              model = "ollama/*";
              api_base = "http://localhost:11434";
            };
          }
          # ── Google Gemini (direct API — cheaper than OpenRouter) ──
          {
            model_name = "gemini/gemini-2.5-flash-lite";
            litellm_params = {
              model = "gemini/gemini-2.5-flash-lite";
              api_key = "os.environ/GEMINI_API_KEY";
            };
          }
          {
            model_name = "gemini/gemini-2.5-flash";
            litellm_params = {
              model = "gemini/gemini-2.5-flash";
              api_key = "os.environ/GEMINI_API_KEY";
            };
          }
          {
            model_name = "gemini/gemini-2.5-pro";
            litellm_params = {
              model = "gemini/gemini-2.5-pro";
              api_key = "os.environ/GEMINI_API_KEY";
            };
          }
          # ── DeepSeek (primary agentic model) ────────────────────────
          {
            model_name = "deepseek/deepseek-chat";
            litellm_params = {
              model = "deepseek/deepseek-chat";
              api_key = "os.environ/DEEPSEEK_API_KEY";
            };
          }
          {
            model_name = "deepseek/deepseek-reasoner";
            litellm_params = {
              model = "deepseek/deepseek-reasoner";
              api_key = "os.environ/DEEPSEEK_API_KEY";
            };
          }
          # ── Anthropic (Claude) ──────────────────────────────────────
          {
            model_name = "claude/claude-sonnet-4-6";
            litellm_params = {
              model = "claude/claude-sonnet-4-6";
              api_key = "os.environ/ANTHROPIC_API_KEY";
            };
          }
          {
            model_name = "claude/claude-haiku-4-5";
            litellm_params = {
              model = "claude/claude-haiku-4-5";
              api_key = "os.environ/ANTHROPIC_API_KEY";
            };
          }
          # ── OpenAI (fallback smol classifier) ───────────────────────
          {
            model_name = "openai/gpt-4.1-nano";
            litellm_params = {
              model = "openai/gpt-4.1-nano";
              api_key = "os.environ/OPENAI_API_KEY";
            };
          }
          {
            model_name = "openai/gpt-4o";
            litellm_params = {
              model = "openai/gpt-4o";
              api_key = "os.environ/OPENAI_API_KEY";
            };
          }
          {
            model_name = "openai/gpt-4o-mini";
            litellm_params = {
              model = "openai/gpt-4o-mini";
              api_key = "os.environ/OPENAI_API_KEY";
            };
          }
          # ── OpenRouter (unified gateway for 300+ models) ────────────
          {
            model_name = "openrouter/*";
            litellm_params = {
              model = "openrouter/*";
              api_key = "os.environ/OPENROUTER_API_KEY";
            };
          }
        ];
        litellm_settings = {
          drop_params = true;
          set_verbose = false;
        };
      };
    in ''
      set -euo pipefail

      mkdir -p /var/lib/litellm /var/lib/litellm/postgres

      # Generate master key if none exists
      if [ ! -f /var/lib/litellm/master-key ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 16 > /var/lib/litellm/master-key
      fi

      # Generate postgres password if none exists
      if [ ! -f /var/lib/litellm/postgres-password ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 16 > /var/lib/litellm/postgres-password
      fi
      chmod 0400 /var/lib/litellm/postgres-password

      # Build the env file with API keys from agenix + generated secrets
      rm -f /var/lib/litellm/env
      if [ -f /run/agenix/llm-runtime-keys ]; then
        cat /run/agenix/llm-runtime-keys >> /var/lib/litellm/env
      fi
      echo "LITELLM_MASTER_KEY=$(cat /var/lib/litellm/master-key)" >> /var/lib/litellm/env
      PG_PASS=$(cat /var/lib/litellm/postgres-password)
      echo "DATABASE_URL=postgresql://litellm:$PG_PASS@litellm-postgres:5432/litellm" >> /var/lib/litellm/env

      # Copy the nix-generated config.yaml into place
      cp ${configFile} /var/lib/litellm/config.yaml
      chmod 0444 /var/lib/litellm/config.yaml

      # Fix permissions so containers can access everything
      chown -R root:root /var/lib/litellm
    '';
  };


  # Ollama (ROCm) for Frigate GenAI. Serves on :11434 via Tailscale + LAN.

  # drones
  services.upower.enable = true;

  # Firewall enabled via shared-cli-configuration.nix.
  networking.firewall.allowPing = true;

  networking.firewall.allowedTCPPorts = [
    4000 # LiteLLM proxy
    10250 # kubelet (k3s agent)
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # flannel VXLAN (k3s)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 30000; to = 32767; } # Kubernetes NodePort range
  ];

  # Allow windows to see the samba share
  #services.samba-wsdd = {
  #enable = true;
  #openFirewall = true;
  #};

  #services.samba = {
  #enable = true;
  #securityType = "user";
  #openFirewall = true;
  #settings = {
  #global = {
  #"workgroup" = "WORKGROUP";
  #"server string" = "smbnix";
  #"netbios name" = "smbnix";
  #"security" = "user";
  ##"use sendfile" = "yes";
  ##"max protocol" = "smb2";
  ## note: localhost is the ipv6 localhost ::1
  #"hosts allow" = "192.168.1. 127.0.0.1 localhost";
  #"hosts deny" = "0.0.0.0/0";
  #"guest account" = "john";
  #"map to guest" = "bad user";
  #};
  #"john_camera_readonly" = {
  #"path" = "/mnt/share/camera/";
  #"browseable" = "yes";
  #"read only" = "yes";
  #"guest ok" = "yes";
  #"create mask" = "0644";
  #"directory mask" = "0755";
  #"force user" = "john";
  #"force group" = "john";
  #};
  #};
  #};

  #programs.ssh.extraConfig = ''
  #Host eu.nixbuild.net
  #PubkeyAcceptedKeyTypes ssh-ed25519
  #ServerAliveInterval 60
  #IPQoS throughput
  #IdentityFile /home/john/.ssh/id_ed25519
  #'';

  #programs.ssh.knownHosts = {
  #nixbuild = {
  #hostNames = [ "eu.nixbuild.net" ];
  #publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
  #};
  #};

  boot.kernel.sysctl = {
    # IPv6 forwarding (set by podman/docker/k3s) suppresses router-advertisement
    # acceptance per-interface. Without an IPv6 default route, the k3s agent
    # (v1.35.4+) cannot auto-detect an IPv6 node-ip, and fails validation
    # against the dual-stack cluster CIDR set by closet (the server).
    # Setting default.accept_ra=2 lets new interfaces (wlp0s20f3 via NM) accept
    # RAs even when forwarding is enabled, restoring the IPv6 default route.
    "net.ipv6.conf.default.accept_ra" = 2;
  };
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?
}
