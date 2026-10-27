{
  description = "On-demand, always-fresh yt-dlp for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkYtDlp = pkgs:
        pkgs.writeShellApplication {
          name = "yt-dlp";

          runtimeInputs = with pkgs; [
            uv
            python3
            ffmpeg
            deno
          ];

          text = ''
            exec uvx \
              --isolated \
              --refresh \
              --no-config \
              --no-managed-python \
              --python ${pkgs.python3}/bin/python3 \
              --prerelease allow \
              --from 'yt-dlp[default]' \
              yt-dlp "$@"
          '';
        };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          ytDlpFresh = mkYtDlp pkgs;
        in
        {
          yt-dlp = ytDlpFresh;
          default = ytDlpFresh;
        });

      overlays.default = final: prev: {
        yt-dlp-fresh = mkYtDlp final;
      };
    };
}
