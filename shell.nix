let
  pkgs = import ./nix { };
in pkgs.mkShell {
  name = "nix-hosts";
  buildInputs = with pkgs; [
    nixopsUnstable
    zola
  ];
  shellHook = "";
}
