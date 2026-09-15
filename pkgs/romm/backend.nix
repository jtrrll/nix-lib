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
  stdenvNoCC,
  writeShellApplication,
}:
let
  python = python313.override {
    self = python;
    packageOverrides = final: prev: {
      crontab = final.callPackage ./crontab.nix { };
      strsimpy = final.callPackage ./strsimpy.nix { };
      zipfile-inflate64 = final.callPackage ./zipfile_inflate64.nix { };
      rq-scheduler = final.callPackage ./rq_scheduler.nix { };

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
        version = "1.0.1";
        src = fetchPypi {
          pname = "starlette";
          inherit version;
          hash = "sha256-USOZxfHef6yZyIVyIS3tnd7d7y+zKvqC1yQADoizj08=";
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
    ps.rq-scheduler
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
  version = "5.2.0";

  src = fetchFromGitHub {
    owner = "rommapp";
    repo = "romm";
    tag = finalAttrs.version;
    hash = "sha256-ixRgaDnyHzHWJjvC5yB6pD88aUgwtnkF6H7snAFODrE=";
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
        update_pypi() {
          local file="$1" project="$2" select="$3" anchor="''${4:-}"
          local latest hex
          echo "==> $project (pypi)"
          latest="$(curl -sfL "https://pypi.org/pypi/$project/json" | jq -r '.info.version')"
          hex="$(curl -sfL "https://pypi.org/pypi/$project/$latest/json" \
            | jq -r "first(.urls[] | select($select) | .digests.sha256) // empty")"
          if [ -z "$hex" ]; then
            echo "::error::no matching release file for $project $latest" >&2
            return 1
          fi
          edit_version_hash "$file" "$latest" "$(nix_sri "$hex")" "$anchor"
        }

        # A pinned fork tracked on its default branch, versioned as
        # <base>-unstable-<commit date>.
        update_github_unstable() {
          local file="$1" owner="$2" repo="$3" base="$4"
          local rev date sri
          echo "==> $owner/$repo (github)"
          rev="$(git ls-remote "https://github.com/$owner/$repo" HEAD | cut -f1)"
          date="$(curl -sfL "https://api.github.com/repos/$owner/$repo/commits/$rev" \
            | jq -r '.commit.committer.date[0:10]')"
          sri="$(nix_sri "$(nix-prefetch-url --unpack \
            "https://github.com/$owner/$repo/archive/$rev.tar.gz")")"
          sed -i \
            -e "s|rev = \"[^\"]*\"|rev = \"$rev\"|" \
            -e "s|version = \"[^\"]*\"|version = \"$base-unstable-$date\"|" \
            -e "s|hash = \"[^\"]*\"|hash = \"$sri\"|" \
            "$file"
        }

        sdist='.packagetype == "sdist"'
        wheel='.packagetype == "bdist_wheel" and (.filename | endswith("py3-none-any.whl"))'

        update_pypi "$root/pkgs/romm/crontab.nix"           crontab           "$sdist"
        update_pypi "$root/pkgs/romm/strsimpy.nix"          strsimpy          "$sdist"
        update_pypi "$root/pkgs/romm/zipfile_inflate64.nix" zipfile-inflate64 "$wheel"
        update_github_unstable "$root/pkgs/romm/rq_scheduler.nix" adamantike rq-scheduler 0.14.0

        backend="$root/pkgs/romm/backend.nix"
        update_pypi "$backend" fastapi            "$sdist" 'fastapi = prev\.fastapi\.overridePythonAttrs'
        update_pypi "$backend" starlette          "$sdist" 'starlette = prev\.starlette\.overridePythonAttrs'
        update_pypi "$backend" fastapi-pagination "$sdist" 'fastapi-pagination = prev\.fastapi-pagination\.overridePythonAttrs'

        # Finally bump the backend release itself.
        ${lib.escapeShellArgs (
          map toString (nix-update-script {
            attrPath = "romm.passthru.backend";
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
