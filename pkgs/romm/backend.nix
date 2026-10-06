{
  lib,
  cacert,
  curl,
  fetchFromGitHub,
  fetchPypi,
  git,
  gnused,
  jq,
  nix-update-script,
  python313,
  rompatcher-js,
  stdenvNoCC,
  writeShellApplication,
}:
let
  python = python313.override {
    self = python;
    packageOverrides = final: prev: {
      strsimpy = final.callPackage ./strsimpy.nix { };
      zipfile-inflate64 = final.callPackage ./zipfile_inflate64.nix { };

      fastapi = prev.fastapi.overridePythonAttrs (_old: rec {
        version = "0.134.0";
        src = fetchPypi {
          pname = "fastapi";
          inherit version;
          hash = "sha256-MSKx6g2+qrSLWXboC5nKftoCvhVL8D4SajMiDnMlWpo=";
        };
        dontUsePytestCheck = true;
      });

      starlette = prev.starlette.overridePythonAttrs (_old: rec {
        version = "1.6.0";
        src = fetchPypi {
          pname = "starlette";
          inherit version;
          hash = "sha256-1OOsXlRkRJYMcQKXo8n8P3664bfpY/PTYXO0naU1vps=";
        };
        dontUsePytestCheck = true;
      });

      fastapi-pagination = prev.fastapi-pagination.overridePythonAttrs (_old: rec {
        version = "0.15.0";
        src = fetchPypi {
          pname = "fastapi_pagination";
          inherit version;
          hash = "sha256-Ef45y+GB7TwYkZuQ+va/y+QMtZaqnFKpi7zoURGimk8=";
        };
      });
    };
  };

  pythonEnv = python.withPackages (ps: [
    ps.aiohttp
    ps.alembic
    ps.anyio
    ps.asyncssh
    ps.authlib
    ps.colorama
    ps.cryptography
    ps.defusedxml
    ps.email-validator
    ps.fastapi
    ps.fastapi-pagination
    ps.gunicorn
    ps.httptools
    ps.httpx
    ps.itsdangerous
    ps.jinja2
    ps.joserfc
    ps.mutagen
    ps.opentelemetry-distro
    ps.opentelemetry-exporter-otlp
    ps.opentelemetry-instrumentation-aiohttp-client
    ps.opentelemetry-instrumentation-fastapi
    ps.opentelemetry-instrumentation-httpx
    ps.opentelemetry-instrumentation-redis
    ps.opentelemetry-instrumentation-sqlalchemy
    ps.passlib
    ps.pillow
    ps.psycopg
    ps.psycopg-c
    ps.pydantic
    ps.pydantic-extra-types
    ps.pydantic-settings
    ps.pydash
    ps.python-dotenv
    ps.python-magic
    ps.python-multipart
    ps.python-socketio
    ps.pyyaml
    ps.redis
    ps.rq
    ps.sentry-sdk
    ps.sqlalchemy
    ps.starlette
    ps.streaming-form-data
    ps.strsimpy
    ps.ua-parser
    ps.unidecode
    ps.uvicorn
    ps.uvicorn-worker
    ps.uvloop
    ps.watchfiles
    ps.websockets
    ps.yarl
    ps.zipfile-inflate64
    ps.zstandard
    # runtime helpers used by the socket/worker layers
    ps.bcrypt
    ps.mysqlclient
  ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "romm-backend";
  version = "5.3.1";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "romm";
    tag = finalAttrs.version;
    hash = "sha256-ijfp4L4GdGbr4FcBo83xVnGEksXawrkK3rYe8/Is+NU=";
  };

  # Upstream's release CI replaces the `<version>` placeholder in
  # __version__.py; without it get_version() reports "development".
  postPatch = ''
    echo '__version__ = "${finalAttrs.version}"' > backend/__version__.py
  '';

  # The backend is run directly from its source tree (uv run python main.py),
  # not installed as a wheel. Ship the source plus a Python environment with all
  # runtime dependencies.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/romm
    cp -r backend $out/share/romm/backend
    cp -r ${rompatcher-js.lib}/share/rompatcher-js/rom-patcher-js $out/share/romm/backend/utils/rom_patcher/rom-patcher-js
    cp -r alembic.ini $out/share/romm/ 2>/dev/null || true
    ln -s ${pythonEnv} $out/share/romm/python-env
    runHook postInstall
  '';

  passthru = {
    inherit pythonEnv;

    updateScript = writeShellApplication {
      name = "update-romm-backend";
      runtimeInputs = [
        cacert
        curl
        git
        gnused
        jq
      ];
      text = ''
        export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
        root="$(git rev-parse --show-toplevel)"

        # Resolve RomM's upcoming release and its locked dependency versions
        # up front, so every PyPI sub-dependency below is pinned against the
        # same `uv.lock` the backend bump at the end of this script will move
        # the `romm` package to.
        tag="$(curl -sfL https://api.github.com/repos/rommapp/romm/releases/latest | jq -r '.tag_name')"
        lock="$(curl -sfL "https://raw.githubusercontent.com/rommapp/romm/$tag/uv.lock")"

        nix_sri() {
          nix --extra-experimental-features nix-command hash convert \
            --hash-algo sha256 --to sri "$1"
        }

        edit_version_hash() {
          local file="$1" version="$2" sri="$3" anchor="''${4:-}"
          local v="s|version = \"[^\"]*\"|version = \"$version\"|"
          local h="s|hash = \"[^\"]*\"|hash = \"$sri\"|"
          if [ -n "$anchor" ]; then
            sed -i "/$anchor/,/hash = / { $v; $h; }" "$file"
          else
            sed -i "$v; $h" "$file"
          fi
        }

        # PROJECT is the PyPI project; SELECT is a jq predicate picking the
        # sdist vs wheel release file.
        #
        # RomM's `pyproject.toml` pins are PEP 440 "compatible release" (~=)
        # ranges, which don't account for *cross*-package constraints (e.g.
        # fastapi-pagination releases newer than 0.15.x require a newer
        # fastapi than RomM itself allows). Blindly fetching PyPI's "latest"
        # release can silently pick a version that's in-range for RomM's own
        # pin but incompatible with its other pinned dependencies. RomM's own
        # `uv.lock` is the ground truth: it's whatever version upstream's
        # resolver already verified is mutually compatible, so read the
        # pinned version from there instead of guessing from "latest".
        locked_version() {
          local project="$1"
          printf '%s\n' "$lock" | awk -v name="$project" '
            $0 == "name = \"" name "\"" { found = 1; next }
            found && /^version = / { gsub(/"/, "", $3); print $3; exit }
          '
        }

        update_pypi() {
          local file="$1" project="$2" select="$3" anchor="''${4:-}"
          local version hex
          echo "==> $project (pypi)"
          version="$(locked_version "$project")"
          if [ -z "$version" ]; then
            echo "::error::$project not found in romm's uv.lock ($tag)" >&2
            return 1
          fi
          hex="$(curl -sfL "https://pypi.org/pypi/$project/$version/json" \
            | jq -r "first(.urls[] | select($select) | .digests.sha256) // empty")"
          if [ -z "$hex" ]; then
            echo "::error::no matching release file for $project $version" >&2
            return 1
          fi
          edit_version_hash "$file" "$version" "$(nix_sri "$hex")" "$anchor"
        }

        sdist='.packagetype == "sdist"'
        wheel='.packagetype == "bdist_wheel" and (.filename | endswith("py3-none-any.whl"))'

        update_pypi "$root/pkgs/romm/strsimpy.nix"          strsimpy          "$sdist"
        update_pypi "$root/pkgs/romm/zipfile_inflate64.nix" zipfile-inflate64 "$wheel"

        backend="$root/pkgs/romm/backend.nix"
        update_pypi "$backend" fastapi            "$sdist" 'fastapi = prev\.fastapi\.overridePythonAttrs'
        update_pypi "$backend" starlette          "$sdist" 'starlette = prev\.starlette\.overridePythonAttrs'
        update_pypi "$backend" fastapi-pagination "$sdist" 'fastapi-pagination = prev\.fastapi-pagination\.overridePythonAttrs'

        # Finally bump the backend release itself.
        ${lib.escapeShellArgs (
          map toString (nix-update-script {
            attrPath = "legacyPackages.${stdenvNoCC.hostPlatform.system}.romm.passthru.backend";
            extraArgs = [ "--flake" ];
          })
        )}
      '';
    };
  };

  meta = {
    description = "Backend application for RomM";
    homepage = "https://romm.app";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
