{ config, lib, ... }:
{
  options.custom.k3sNodeTaints = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Node taints to apply when the k3s agent first registers.";
    example = [ "seated=true:NoSchedule" ];
  };

  config = {
    age.identityPaths = [ "/home/john/.ssh/age" ];
    age.secrets.k3s-local-token = {
      file = ../../secrets/k3s-local-token.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    services.k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://192.168.1.35:6443";
      tokenFile = config.age.secrets.k3s-local-token.path;
    };
  };
}
