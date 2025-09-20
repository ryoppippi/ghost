{
  description = "Ghost application flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forEachSystem = f: lib.genAttrs systems f;
      cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
      packageName = cargoToml.package.name;
      packageVersion = cargoToml.package.version or "git";
      rustToolchain = builtins.fromTOML (builtins.readFile ./rust-toolchain.toml);
      rustChannel = rustToolchain.toolchain.channel or "stable";
      sanitizeVersion = version: builtins.replaceStrings [ "." ] [ "_" ] version;
      selectRustPackages = pkgs:
        let
          candidate = "rustPackages_" + sanitizeVersion rustChannel;
        in
        if builtins.hasAttr candidate pkgs then builtins.getAttr candidate pkgs else pkgs.rustPackages;
      mkRustPlatform = pkgs:
        let rustPkgs = selectRustPackages pkgs;
        in pkgs.makeRustPlatform {
          cargo = rustPkgs.cargo;
          rustc = rustPkgs.rustc;
        };
      darwinFrameworksFor = pkgs:
        pkgs.lib.optionals pkgs.stdenv.isDarwin [];
    in
    rec {
      packages = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rustPlatform = mkRustPlatform pkgs;
        in
        {
          default = rustPlatform.buildRustPackage {
            pname = packageName;
            version = packageVersion;
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;
            doCheck = false;
            nativeBuildInputs = [ pkgs.pkg-config pkgs.lsof ];
            buildInputs = darwinFrameworksFor pkgs;
            meta = with pkgs.lib; {
              description = "Simple background process manager with a TUI for Unix-like systems.";
              homepage = "https://github.com/skanehira/ghost";
              license = licenses.mit;
              mainProgram = packageName;
              platforms = platforms.unix;
            };
          };
        }
      );

      apps = forEachSystem (system: {
        default = {
          type = "app";
          program = "${packages.${system}.default}/bin/${packageName}";
        };
      });

      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rustPkgs = selectRustPackages pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [
              rustPkgs.rustc
              rustPkgs.cargo
              pkgs.pkg-config
              pkgs.lsof
            ];
            buildInputs = darwinFrameworksFor pkgs;
            RUST_BACKTRACE = "1";
            RUSTUP_TOOLCHAIN = rustChannel;
          };
        });
    };
}
