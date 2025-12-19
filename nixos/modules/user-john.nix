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
    obsidian # note-taking software
    pkgs-stable.teamspeak_client
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
    packages =
      if compName == "office" then unfreePackages else
      if compName == "arch" then unfreePackages else
      [];
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
