let
  pkgs = import ./nix { };
in pkgs.mkShell {
  name = "nix-hosts";
  buildInputs = with pkgs; [
    nixopsUnstable
    zola
  ];

  # Export all environment variables available in the .env file, so they can
  # be used by NixOps.
  shellHook = "while read -r line; do export $line; done < .env";
}
