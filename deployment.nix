# Needed to use the getEnv function. Environment variables will be loaded from
# the file .env when starting nix-shell.
with builtins;

let
  pkgs = import ./nix { };
  home-manager = builtins.fetchGit {
    url = "https://github.com/nix-community/home-manager.git";
    rev = "148d85ee8303444fb0116943787aa0b1b25f94df";
    ref = "release-21.05";
  };
in {
  network = { description = "nix-hosts"; };
  defaults = {
    imports = [ (import "${home-manager}/nixos") ];
  };
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
    networking.firewall = {
      allowedTCPPorts = [ 80 443 ];
      pingLimit = "--limit 1/minute --limit-burst 5";
      extraCommands = ''
        iptables -A INPUT -s ${getEnv "LOCAL_IP"} -j ACCEPT
        iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
      '';
    };
    time.timeZone = "America/Sao_Paulo";

    users = {
      mutableUsers = false;
      users = {
        "${getEnv "ADMIN"}" = {
          isNormalUser = true;
          # Needed to be able to be able to run sudo without password.
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = (import ./keys.nix);
        };
      };
      # This will be used for distributed builds.
      users = {
        root = {
          isSystemUser = true;
          openssh.authorizedKeys.keys = (import ./keys.nix);
        };
      };
    };

    home-manager = {
      users = {
        ${getEnv "ADMIN"} = {
          programs = {
            tmux = {
              enable = true;
            };
            htop = {
              enable = true;
            };
            neovim = {
              enable = true;
              viAlias = true;
              vimAlias = true;
            };
          };
        };
      };
    };

    environment.systemPackages = with pkgs; [
      goaccess
    ];

    services = {
      openssh = {
        enable = true;
        permitRootLogin = "prohibit-password";
        passwordAuthentication = false;
      };

      sshguard = {
        enable = true;
        blocktime = 900;
        attack_threshold = 30;
        # This will block the IP definitely.
        blacklist_threshold = 50;
        whitelist = [ (getEnv "LOCAL_IP") ];
      };

      fail2ban = {
        enable = true;
        ignoreIP = [ (getEnv "LOCAL_IP") ];
      };

      searx = {
        enable = true;
        settings = {
          server.secret_key = (getEnv "SEARX_SECRET_KEY");
        };
      };

      prometheus = {
        enable = true;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = [ "systemd" ];
          };
          nginx = {
            enable = true;
          };
        };
        scrapeConfigs = [
          {
            job_name = "prometheus";
            static_configs = [
              {
                targets = [ "localhost:9090" ];
              }
            ];
          }
          {
            job_name = "node";
            static_configs = [
              {
                targets = [ "localhost:9100" ];
              }
            ];
          }
          {
            job_name = "nginx";
            static_configs = [
              {
                targets = [ "localhost:9113" ];
              }
            ];
          }
        ];
      };

      # After deployed, add the dashboards 1860, 6927, and 405 and you are good
      # to go. 9629 for Fail2ban monitoring. 11074 for a more complete
      # overview.
      grafana = {
        enable = true;
        # Despite having defined the credentials here, I still had to set admin
        # password when accessing Grafana the first time.
        # security = {
          # Security warning: Grafana passwords will be stored as plain text in
          # the Nix store.
          # adminUser = "admin";
          # adminPassword = "somerandompassword";
        # };
        provision = {
          enable = true;
          # Needs to be type `list of submodules'. See more about datasources
          # in https://grafana.com/docs/grafana/latest/datasources/prometheus/
          # Still not sure if these data sources are correct.
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://localhost:9090";
              # Use direct when accessing Prometheus from the browser.
              # Use proxy when accessing through Grafana.
              access = "proxy";
            }
            {
              name = "Node";
              type = "prometheus";
              url = "http://localhost:9100";
              access = "proxy";
            }
            {
              name = "Nginx";
              type = "prometheus";
              url = "http://localhost:9113";
              access = "proxy";
            }
          ];
        };
      };

      nginx = {
        enable = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
        virtualHosts = {
          "mrioqueiroz.com" = {
            default = true;
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
            forceSSL = true;
            # Needs to define this option to avoid "option sslCertificate used
            # but not defined" error when addSSL is set to true.
            enableACME = true;
          };
          "grafana.mrioqueiroz.com" = {
            locations."/".proxyPass = "http://localhost:3000";
            forceSSL = true;
            enableACME = true;
          };
          "searx.mrioqueiroz.com" = {
            locations."/".proxyPass = "http://localhost:8888";
            forceSSL = true;
            enableACME = true;
          };
          # Close connection without response if trying to access the website
          # using the IP address.
          "${(getEnv "TARGET_IP")}" = {
            locations."/".return = "444";
          };
        };
      };
    };
  };
}
