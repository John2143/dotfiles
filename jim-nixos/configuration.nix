{ pkgs, ... }: {
  # Boot — systemd-boot for EFI, matches the 2G ESP in disko
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Network
  networking.hostName = "jim";
  networking.networkmanager.enable = true;

  # User account — change password on first login with `passwd`
  users.users.jim = {
    isNormalUser = true;
    initialPassword = "changeme";
    extraGroups = [ "wheel" "networkmanager" ];
  };

  # Remote access (optional — remove if unwanted)
  services.openssh.enable = true;

  # Bare essentials
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
  ];

  system.stateVersion = "25.11";
}
