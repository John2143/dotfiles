{
  #config,
  pkgs,
  pkgs-stable,
  compName,
  ...
}:

let
  unfreePackages = with pkgs; [
  ];
in
{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    extraGroups = [
      "wheel" # to use sudo
      "networkmanager" # to manage network connections
      "input" # to access input devices
      "dialout" # for serial devices like Arduino
      "docker" # to use docker without sudo
      "ydotool" # can act as a virtual keyboard and mouse
      "seat" # used for login with lemurs
    ];
    initialPassword = "john";
    shell = pkgs.fish;
    packages = [];
  };
  security.sudo.wheelNeedsPassword = false;

  home-manager = {
    # home-manager uses extraSpecialArgs instead of specialArgs, but it does the same thing
    extraSpecialArgs = {
      pkgs-stable = pkgs-stable;
      compName = compName;
    };
    #sharedModles = [
    #inputs.sops-nix.homeManagerModles.sops
    #];
  };
}
