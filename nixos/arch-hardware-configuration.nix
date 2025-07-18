# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.kernelParams = [
    "video=DP-1:2560x1440@240"
    "video=HDMI-A-2:2560x1440@144"
  ];
  boot.extraModulePackages = [ ];
  boot.extraModprobeConfig = '''';
  #blacklist nouveau
  #options nouveauu modeset=0

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIX";
    fsType = "ext4";
  };

  fileSystems."/mnt/arch" = {
    device = "/dev/disk/by-label/ARCH";
    fsType = "ext4";
  };

  fileSystems."/mnt/other" = {
    device = "/dev/disk/by-label/OTHER";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/FD0B-76B7";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  fileSystems."/mnt/efi1" = {
    device = "/dev/disk/by-uuid/C84B-9CD5";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  fileSystems."/mnt/efi2" = {
    device = "/dev/disk/by-uuid/B06A-EB76";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.cni0.useDHCP = lib.mkDefault true;
  # networking.interfaces.eno1.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  # networking.interfaces.flannel.1.useDHCP = lib.mkDefault true;
  # networking.interfaces.veth6a78d611.useDHCP = lib.mkDefault true;
  # networking.interfaces.veth8d9e6a9e.useDHCP = lib.mkDefault true;
  # networking.interfaces.vethe2047d77.useDHCP = lib.mkDefault true;
  # networking.interfaces.wg0-mullvad.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp5s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = false;
    modesetting.enable = true;
    nvidiaSettings = true;
  };

  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot
}
