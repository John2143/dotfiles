{
  #config,
  pkgs,
  pkgs-stable,
  john-home-path,
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
      "wheel"
      "networkmanager"
      "input"
      "dialout"
      "docker"
      "ydotool"
    ]; # Enable ‘sudo’ for the user.
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
    users = {
      "john" = import john-home-path;
    };
  };
}
