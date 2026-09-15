{
  lib,
  callPackage,
  writeShellApplication,
  bash,
  coreutils,
  # RAHasher is optional (only needed for RetroAchievements hashes); the
  # deployment decides whether to provide it. When null it is simply absent
  # from the runtime PATH.
  rahasher ? null,
}:
let
  backend = callPackage ./backend.nix { };
  frontend = callPackage ./frontend.nix { };
  inherit (backend.passthru) pythonEnv;

  # Entrypoint mirroring upstream's entrypoint.sh: start the backend, RQ
  # scheduler, RQ worker and the library watcher, using the pre-built Python
  # environment instead of `uv run`. The static frontend is served separately
  # by the deployment (e.g. the NixOS module's container/nginx).
  entrypoint = writeShellApplication {
    name = "romm";
    runtimeInputs = [
      bash
      coreutils
      pythonEnv
    ]
    ++ lib.optional (rahasher != null) rahasher;
    text = ''
      export ROMM_BASE_PATH="''${ROMM_BASE_PATH:-/romm}"
      export PYTHONUNBUFFERED=1
      export PYTHONDONTWRITEBYTECODE=1

      backend_dir="${backend}/share/romm/backend"
      gunicorn_socket="''${GUNICORN_SOCKET:-/run/romm/gunicorn.sock}"

      handle_termination() {
        echo "Terminating child processes..."
        kill -TERM "$(jobs -p)" 2>/dev/null || true
      }
      trap handle_termination SIGTERM SIGINT

      if [[ -z "''${ROMM_AUTH_SECRET_KEY:-}" ]]; then
        ROMM_AUTH_SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
        export ROMM_AUTH_SECRET_KEY
      fi

      # opentelemetry-instrument's sitecustomize.py shadows nixpkgs', dropping NIX_PYTHONPATH.
      # Put site-packages on PYTHONPATH so imports survive.
      site_packages="$(python -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
      export PYTHONPATH="$site_packages''${PYTHONPATH:+:$PYTHONPATH}"

      cd "$backend_dir"

      echo "Running database migrations..."
      alembic upgrade head

      echo "Running startup tasks..."
      python startup.py

      echo "Starting backend (gunicorn)..."
      rm -f "$gunicorn_socket"
      opentelemetry-instrument \
        --service_name "''${OTEL_SERVICE_NAME_PREFIX:-}api" \
        gunicorn \
        --bind="unix:$gunicorn_socket" \
        --forwarded-allow-ips="*" \
        --worker-class uvicorn_worker.UvicornWorker \
        --workers "''${WEB_SERVER_CONCURRENCY:-1}" \
        --timeout "''${WEB_SERVER_TIMEOUT:-300}" \
        --keep-alive "''${WEB_SERVER_KEEPALIVE:-2}" \
        --max-requests "''${WEB_SERVER_MAX_REQUESTS:-1000}" \
        --max-requests-jitter "''${WEB_SERVER_MAX_REQUESTS_JITTER:-100}" \
        --worker-connections "''${WEB_SERVER_WORKER_CONNECTIONS:-1000}" \
        --error-logfile - \
        main:app &

      echo "Starting RQ scheduler..."
      RQ_REDIS_HOST="''${REDIS_HOST:-127.0.0.1}" \
        RQ_REDIS_PORT="''${REDIS_PORT:-6379}" \
        RQ_REDIS_USERNAME="''${REDIS_USERNAME:-}" \
        RQ_REDIS_PASSWORD="''${REDIS_PASSWORD:-}" \
        RQ_REDIS_DB="''${REDIS_DB:-0}" \
        RQ_REDIS_SSL="''${REDIS_SSL:-0}" \
        rqscheduler --path "$backend_dir" --pid /run/romm/rq_scheduler.pid &

      echo "Starting RQ worker..."
      if [[ -n "''${REDIS_PASSWORD:-}" ]]; then
        REDIS_URL="redis''${REDIS_SSL:+s}://''${REDIS_USERNAME:-}:''${REDIS_PASSWORD}@''${REDIS_HOST:-127.0.0.1}:''${REDIS_PORT:-6379}/''${REDIS_DB:-0}"
      elif [[ -n "''${REDIS_USERNAME:-}" ]]; then
        REDIS_URL="redis''${REDIS_SSL:+s}://''${REDIS_USERNAME}@''${REDIS_HOST:-127.0.0.1}:''${REDIS_PORT:-6379}/''${REDIS_DB:-0}"
      else
        REDIS_URL="redis''${REDIS_SSL:+s}://''${REDIS_HOST:-127.0.0.1}:''${REDIS_PORT:-6379}/''${REDIS_DB:-0}"
      fi

      PYTHONPATH="$backend_dir:''${PYTHONPATH:-}" rq worker \
        --path "$backend_dir" \
        --pid /run/romm/rq_worker.pid \
        --url "$REDIS_URL" \
        high default low &

      echo "Starting watcher..."
      watchfiles \
        --target-type command \
        'python watcher.py' \
        "$ROMM_BASE_PATH/library" &

      wait
    '';
  };
in
entrypoint.overrideAttrs (old: {
  pname = "romm";
  inherit (backend) version;

  passthru = (old.passthru or { }) // {
    inherit
      backend
      frontend
      pythonEnv
      ;

    updateScript = writeShellApplication {
      name = "update-romm";
      text =
        let
          toCommand =
            script: if lib.isList script then lib.escapeShellArgs (map toString script) else lib.getExe script;
        in
        lib.concatMapStringsSep "\n" toCommand [
          backend.passthru.updateScript
          frontend.passthru.updateScript
        ];
    };
  };

  meta = (old.meta or { }) // {
    description = "Self-hosted ROM manager and player";
    homepage = "https://romm.app";
    license = lib.licenses.agpl3Only;
    mainProgram = "romm";
    maintainers = [
      lib.maintainers.jtrrll
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
