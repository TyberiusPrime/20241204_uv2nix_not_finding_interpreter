{
  description = "A basic flake using uv2nix";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/684a8fe32d4b7973974e543eed82942d2521b738";
    uv2nix.url = "github:/pyproject-nix/uv2nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix_hammer_overrides.url = "github:tyberiusprime/uv2nix_hammer_overrides";
    uv2nix_hammer_overrides.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-nix.url = "github:/pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    nixpkgs,
    uv2nix,
    uv2nix_hammer_overrides,
    #pyproject-nix,
    pyproject-build-systems,
    ...
  }: let
    #inherit (nixpkgs) lib;
    lib = nixpkgs.lib // {match = builtins.match;};

    pyproject-nix = uv2nix.inputs.pyproject-nix;
    workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

    pkgs = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    defaultPackage = let
      # Generate overlay
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      pyprojectOverrides = lib.composeManyExtensions [
        (uv2nix_hammer_overrides.overrides_strict pkgs)
        (
          final: prev: {
            gsignals = prev.gsignals.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ (final.resolveBuildSystem {setuptools = [];});
            });
              # we're going to need this...
            scribes-helpers = prev.scribes-helpers.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ (final.resolveBuildSystem {setuptools = [];});
            });
          }
        )
      ];
      python = pkgs.python39;
      spec = {
        uv2nix-hammer-app = [];
      };

      # Construct package set
      pythonSet =
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        })
        .overrideScope
        (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        );
      # Override host packages with build fixups
    in
      # Render venv
      pythonSet.mkVirtualEnv "test-venv" spec;
  in {
    packages.x86_64-linux.default = defaultPackage;
    # TODO: A better mkShell withPackages example.
  };
}
