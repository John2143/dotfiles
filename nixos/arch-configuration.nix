# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [
      ./arch-hardware-configuration.nix
      # inputs.home-manager.nixosModules.default
    ];

  # === BEGIN NONFREE ===
  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "electron-25.9.0"
    ];
  };
  # === END NONFREE ===

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use the systemd-boot EFI boot loader.
  #boot.loader.systemd-boot.enable = true;
  boot.loader = {
    efi.canTouchEfiVariables = true;
    grub = {
      enable = true;
      device = "nodev";
    };
  };

  fonts.packages = with pkgs; [
    scientifica
  ];

  networking.hostName = "arch"; # Define your hostname.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  networking.interfaces = {
    enp6s0.ipv4.addresses = [{
      address = "192.168.1.3";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "1.1.1.1" ];
  # networking.nameservers = [ "192.168.1.2" "192.168.1.35" ];

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
  sound.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.john = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "input" ]; # Enable ‘sudo’ for the user.
    initialPassword = "john";
    shell = pkgs.fish;
    packages = with pkgs; [
      # === BEGIN NONFREE ===
      obsidian # note-taking software
      teamspeak_client
      discord

      # ======== X =========
      # bspwm
      # xorg.xinit
      # polybarFull
      # ======== X =========


      # nvidia_x11
      # nvidia_settings
      # nvidia_persistenced
      # === END NONFREE ===
    ];
  };
  security.sudo.wheelNeedsPassword = false;


  # ======== X =========

  # services.xserver = {
  #   enable = true;
  #   layout = "us";
  #   xkbOptions = "ctrl:nocaps";
  #   windowManager = {
  #     bspwm.enable = true;
  #     # default = "bspwm";
  #     bspwm = {
  #       configFile = ../.config/bspwm/bspwmrc;
  #       sxhkd.configFile = ../.config/sxhkd/sxhkdrc;
  #     };
  #   };
  # };

  # ======== X =========

  home-manager = {
    users = {
      "john" = import ./home.nix;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    fish
    wget
    curl
    tmux
    vim
    btop

    k3s # kubernetes k8s node

    pavucontrol # audio
    qpwgraph
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  programs.hyprland = {
    enable = true;
  };

  programs.fish.enable = true;

  programs.steam.enable = true;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  services.mullvad-vpn = {
    enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.extraConfig = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
      };
    };
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };

  services.udisks2.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # TODO udiskie
  # services.udiskie.enable = true;

  # services.k3s = {
  #   enable = true;
  #   role = "agent";
  #   serverAddr = "https://192.168.1.2:6443";
  #   token = "K109bf3d3db3a886f74e3b580da672b54e15f0197c0d922c5f3186a8abd2ba36b00::server:cc13ddec0fa20ac3f2c1b3912dab21fb";
  # };

  services.blueman.enable = true;


  # # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 
  #   5353 # avahi
  #   7777 # games
  # ];
  # networking.firewall.allowedUDPPorts = [  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11";
  
  boot.loader.grub.extraEntries = ''
    #
    # DO NOT EDIT THIS FILE
    #
    # It is automatically generated by grub-mkconfig using templates
    # from /etc/grub.d and settings from /etc/default/grub
    #
    
    ### BEGIN /etc/grub.d/00_header ###
    insmod part_gpt
    insmod part_msdos
    if [ -s $prefix/grubenv ]; then
      load_env
    fi
    if [ "$${next_entry}" ] ; then
       set default="$${next_entry}"
       set next_entry=
       save_env next_entry
       set boot_once=true
    else
       set default="0"
    fi
    
    if [ x"$${feature_menuentry_id}" = xy ]; then
      menuentry_id_option="--id"
    else
      menuentry_id_option=""
    fi
    
    export menuentry_id_option
    
    if [ "$${prev_saved_entry}" ]; then
      set saved_entry="$${prev_saved_entry}"
      save_env saved_entry
      set prev_saved_entry=
      save_env prev_saved_entry
      set boot_once=true
    fi
    
    function savedefault {
      if [ -z "$${boot_once}" ]; then
        saved_entry="$${chosen}"
        save_env saved_entry
      fi
    }
    
    function load_video {
      if [ x$feature_all_video_module = xy ]; then
        insmod all_video
      else
        insmod efi_gop
        insmod efi_uga
        insmod ieee1275_fb
        insmod vbe
        insmod vga
        insmod video_bochs
        insmod video_cirrus
      fi
    }
    
    if [ x$feature_default_font_path = xy ] ; then
       font=unicode
    else
    insmod part_gpt
    insmod ext2
    search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
        font="/usr/share/grub/unicode.pf2"
    fi
    
    if loadfont $font ; then
      set gfxmode=auto
      load_video
      insmod gfxterm
      set locale_dir=$prefix/locale
      set lang=en_US
      insmod gettext
    fi
    terminal_input console
    terminal_output gfxterm
    if [ x$feature_timeout_style = xy ] ; then
      set timeout_style=menu
      set timeout=5
    # Fallback normal timeout code in case the timeout_style feature is
    # unavailable.
    else
      set timeout=5
    fi
    ### END /etc/grub.d/00_header ###
    
    ### BEGIN /etc/grub.d/10_linux ###
    menuentry 'Arch Linux' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-simple-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    	load_video
    	set gfxpayload=keep
    	insmod gzio
    	insmod part_gpt
    	insmod ext2
    	search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    	echo	'Loading Linux linux ...'
    	linux	/boot/vmlinuz-linux root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    	echo	'Loading initial ramdisk ...'
    	initrd	/boot/initramfs-linux.img
    }
    submenu 'Advanced options for Arch Linux' $menuentry_id_option 'gnulinux-advanced-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    	menuentry 'Arch Linux, with Linux linux-zen' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-zen-advanced-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux-zen ...'
    		linux	/boot/vmlinuz-linux-zen root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux-zen.img
    	}
    	menuentry 'Arch Linux, with Linux linux-zen (fallback initramfs)' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-zen-fallback-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux-zen ...'
    		linux	/boot/vmlinuz-linux-zen root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux-zen-fallback.img
    	}
    	menuentry 'Arch Linux, with Linux linux-lts' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-lts-advanced-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux-lts ...'
    		linux	/boot/vmlinuz-linux-lts root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux-lts.img
    	}
    	menuentry 'Arch Linux, with Linux linux-lts (fallback initramfs)' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-lts-fallback-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux-lts ...'
    		linux	/boot/vmlinuz-linux-lts root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux-lts-fallback.img
    	}
    	menuentry 'Arch Linux, with Linux linux' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-advanced-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux ...'
    		linux	/boot/vmlinuz-linux root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux.img
    	}
    	menuentry 'Arch Linux, with Linux linux (fallback initramfs)' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-linux-fallback-6b0153d6-70d0-4d48-bcc5-3b1886aa54d0' {
    		load_video
    		set gfxpayload=keep
    		insmod gzio
    		insmod part_gpt
    		insmod ext2
    		search --no-floppy --fs-uuid --set=root 6b0153d6-70d0-4d48-bcc5-3b1886aa54d0
    		echo	'Loading Linux linux ...'
    		linux	/boot/vmlinuz-linux root=UUID=6b0153d6-70d0-4d48-bcc5-3b1886aa54d0 rw  loglevel=3 quiet
    		echo	'Loading initial ramdisk ...'
    		initrd	/boot/initramfs-linux-fallback.img
    	}
    }
    
    ### END /etc/grub.d/10_linux ###
    
    ### BEGIN /etc/grub.d/20_linux_xen ###
    ### END /etc/grub.d/20_linux_xen ###
    
    ### BEGIN /etc/grub.d/25_bli ###
    if [ "$grub_platform" = "efi" ]; then
      insmod bli
    fi
    ### END /etc/grub.d/25_bli ###
    
    ### BEGIN /etc/grub.d/30_os-prober ###
    menuentry 'Windows Boot Manager (on /dev/nvme0n1p7)' --class windows --class os $menuentry_id_option 'osprober-efi-C84B-9CD5' {
    	insmod part_gpt
    	insmod fat
    	search --no-floppy --fs-uuid --set=root C84B-9CD5
    	chainloader /efi/Microsoft/Boot/bootmgfw.efi
    }
    menuentry 'Windows Boot Manager (on /dev/nvme1n1p2)' --class windows --class os $menuentry_id_option 'osprober-efi-FD0B-76B7' {
    	insmod part_gpt
    	insmod fat
    	search --no-floppy --fs-uuid --set=root FD0B-76B7
    	chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    }
    ### END /etc/grub.d/30_os-prober ###
    
    ### BEGIN /etc/grub.d/30_uefi-firmware ###
    if [ "$grub_platform" = "efi" ]; then
    	fwsetup --is-supported
    	if [ "$?" = 0 ]; then
    		menuentry 'UEFI Firmware Settings' $menuentry_id_option 'uefi-firmware' {
    			fwsetup
    		}
    	fi
    fi
    ### END /etc/grub.d/30_uefi-firmware ###
    
    ### BEGIN /etc/grub.d/40_custom ###
    # This file provides an easy way to add custom menu entries.  Simply type the
    # menu entries you want to add after this comment.  Be careful not to change
    # the 'exec tail' line above.
    ### END /etc/grub.d/40_custom ###
    
    ### BEGIN /etc/grub.d/41_custom ###
    if [ -f  $${config_directory}/custom.cfg ]; then
      source $${config_directory}/custom.cfg
    elif [ -z "$${config_directory}" -a -f  $prefix/custom.cfg ]; then
      source $prefix/custom.cfg
    fi
    ### END /etc/grub.d/41_custom ###
  '';
}


