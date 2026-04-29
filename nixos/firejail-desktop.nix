{pkgs, ...}: {
  # Sandbox desktop apps with large attack surfaces (browser content, chat
  # network input). Firejail's pre-built profiles handle the integration
  # plumbing (DBus, portals, GPU, audio) that a hand-rolled bwrap recipe
  # would have to enumerate. Setuid-root tradeoff accepted on workstations.
  #
  # PATH order on NixOS: /run/wrappers/bin (where these wrappers live) comes
  # before /etc/profiles/per-user/john/bin, so the home-manager-installed
  # firefox/chromium/discord stay installed but are shadowed by the
  # firejailed wrappers at runtime.
  programs.firejail = {
    enable = true;

    wrappedBinaries = {
      firefox = {
        executable = "${pkgs.firefox}/bin/firefox";
        profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
      };

      # If chromium fails to start ("Failed to move to new namespace" /
      # chrome-sandbox seccomp clash), drop a local override at
      # ~/.config/firejail/chromium.local with `ignore seccomp` and
      # `ignore noroot`, or temporarily comment this entry while diagnosing.
      chromium = {
        executable = "${pkgs.ungoogled-chromium}/bin/chromium";
        profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
      };

      discord = {
        executable = "${pkgs.discord}/bin/discord";
        profile = "${pkgs.firejail}/etc/firejail/discord.profile";
      };
    };
  };
}
