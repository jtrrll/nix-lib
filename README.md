# nix-lib

<!-- markdownlint-disable MD013 -->
![CI Status](https://img.shields.io/github/actions/workflow/status/jtrrll/nix-lib/ci.yaml?branch=main&label=ci&logo=github)
![License](https://img.shields.io/github/license/jtrrll/nix-lib?label=license&logo=googledocs&logoColor=white)
<!-- markdownlint-enable MD013 -->

A reusable Nix library for jtrrll's repositories.

## Usage

This is a plain Nix library, not a flake. Add it as a `flake = false`
input:

```nix
{
  inputs = {
    nix-lib = {
      flake = false;
      url = "github:jtrrll/nix-lib";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs: {
    ...
  };
}
```

Then import it with a nixpkgs `lib`. It returns an
attribute set of `lib`, `modules`, and `overlays`:

```nix
inputs:
let
  inherit (import inputs.nix-lib { inherit (inputs.nixpkgs) lib; })
    lib
    modules
    overlays
    ;
in
{
  # Apply the package overlay to access the new packages and extended lib.
  nixpkgs' = import inputs.nixpkgs {
    inherit system;
    overlays = [ overlays.default ];
  };

  # Access reusable modules, grouped by class.
  # Each class exposes its individual modules and a `default` that imports all of them.
  myNixosConfiguration = lib.nixosSystem {
    modules = [
      modules.nixos.default
      {
        nixpkgs.overlays = [ overlays.default ];
      }
      {
        ...
      }
    ];
  };

  # Use the extended lib directly.
  transformedString = lib.strings.snakeToCamel "foo_bar";
}
```

## Outputs

### `apps`

<details>
<summary>Show 3</summary>

- `github-tf` - Manages GitHub repository with OpenTofu

- `update-packages` - Runs each package's own updateScript

- `write-files` - Write all configured files to their paths

</details>

### `checks`

<details>
<summary>Show 15</summary>

- `files:.github/CODEOWNERS`

- `files:.github/CODE_OF_CONDUCT.md`

- `files:.github/CONTRIBUTING.md`

- `files:.github/ISSUE_TEMPLATE/bug_report.yaml`

- `files:.github/ISSUE_TEMPLATE/config.yaml`

- `files:.github/ISSUE_TEMPLATE/documentation_issue.yaml`

- `files:.github/ISSUE_TEMPLATE/feature_request.yaml`

- `files:.github/PULL_REQUEST_TEMPLATE.md`

- `files:.github/dependabot.yaml`

- `files:.github/workflows/ci.yaml`

- `files:.github/workflows/update-packages.yaml`

- `files:LICENSE`

- `files:README.md`

- `lib`

- `treefmt`

</details>

### `devShells`

<details>
<summary>Show 1</summary>

- `default`

</details>

### `formatter`

### `overlays`

<details>
<summary>Show 1</summary>

- `default`

</details>

### `packages`

## License

This repository is licensed under the terms in [`LICENSE`](./LICENSE).

That license covers the repository's own code (the library, overlays,
and module definitions). It does **not** inherently apply to the
packages built by this repository. Some of them package third-party
software with its own licensing. Consult each package's individual
license before use or redistribution.
