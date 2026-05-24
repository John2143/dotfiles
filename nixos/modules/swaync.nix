{pkgs, ...}: {
  services.swaync = {
    enable = true;
    style = ../../.config/swaync/style.css;
    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      cssPriority = "application";
      control-center-margin-top = 12;
      control-center-margin-bottom = 12;
      control-center-margin-right = 12;
      control-center-margin-left = 12;
      control-center-width = 420;
      control-center-height = 600;
      notification-window-width = 420;
      timeout = 5;
      timeout-low = 3;
      timeout-critical = 0;
      fit-to-screen = true;
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      transition-time = 200;
      hide-on-clear = false;
      hide-on-action = true;
      script-fail-notify = true;

      widgets = [
        "title"
        "mpris"
        "dnd"
        "notifications"
      ];

      "widget-config" = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
        mpris = {
          image-size = 64;
          image-radius = 8;
        };
      };
    };
  };
}
