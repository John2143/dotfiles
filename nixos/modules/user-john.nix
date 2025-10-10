{
  config,
  pkgs,
  pkgs-stable,
  john-home-path,
  compName,
  ...
}:

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
    ]; # Enable ‘sudo’ for the user.
    initialPassword = "john";
    shell = pkgs.fish;
    packages = with pkgs; [
      obsidian # note-taking software
      pkgs-stable.teamspeak_client
    ];
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
