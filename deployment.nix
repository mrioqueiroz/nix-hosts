# Needed to use the getEnv function. Environment variables will be loaded from
# the file .env when starting nix-shell.
with builtins;

let
  pkgs = import ./nix { };
in {
  network = { description = "nix-hosts"; };
  server = { ... }: {
    deployment = {
      # The keys are defined bellow. If set to true (the default value), we 
      # will not be able to SSH directly into the VM with the default local
      # SSH keys. This was also causing problems to send new configurations.
      provisionSSHKey = false;
      targetHost = (getEnv "TARGET_IP");
      targetUser = (getEnv "ADMIN");
    };

    # Added because of "lacks a valid signature" error when deploying certain
    # options. It was necessary to restart the VM to its original state to
    # make this work.
    nix.trustedUsers = [ "root" "@wheel" ];

    # Some machines use legacy mode to boot. Using the default value for GRUB
    # version (2), may cause the machine to not start after a reboot.
    boot.loader.grub = { enable = true; version = 1; device = "nodev"; };
    fileSystems."/".device = "/dev/disk/by-label/nixos";
    security.sudo.wheelNeedsPassword = false;
    security.acme = { email = (getEnv "ADMIN_EMAIL"); acceptTerms = true; };
    networking.firewall.allowedTCPPorts = [ 80 443 ];
    time.timeZone = "America/Sao_Paulo";

    users = {
      mutableUsers = false;
      users = {
        "${(getEnv "ADMIN")}" = {
          isNormalUser = true;
          # Needed to be able to be able to run sudo without password.
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = (import ./keys.nix);
        };
      };
    };

    services = {
      openssh = {
        enable = true;
        permitRootLogin = "no";
        passwordAuthentication = false;
      };

      nginx = {
        enable = true;
        virtualHosts."mrioqueiroz.com" = {
          locations."/".root = (
            # Build the website with Zola and make it available to Nginx. It
            # would also be possible to put it on a different file (say
            # ./default.nix) and import this derivation with (import ./.).
            let src = ./mrioqueiroz.com; in
            pkgs.stdenv.mkDerivation {
              buildInputs = with pkgs; [ zola ];
              name = "static-site";
              phases = "installPhase";
              installPhase = "cd ${src} && zola build -o $out";
            });
            # As the website is behind Cloudflare, these options are needed to
            # make sure the port 443 is open and, consequently, avoid the 521
            # error.
            addSSL = true;
            enableACME = true;
          };
        };
      };
    };
  }
