let
  module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.romm;

      redisPort = 6379;

      decodeJs = pkgs.writeText "decode.js" ''
        function decodeBase64(r) {
          var encodedValue = r.args.value;
          if (!encodedValue) {
            r.return(400, "Missing 'value' query parameter");
            return;
          }
          try {
            r.return(200, atob(encodedValue));
          } catch (e) {
            r.return(400, "Invalid Base64 encoding");
          }
        }
        export default { decodeBase64 };
      '';

      # Coerce freeform settings values to the strings systemd's `environment`
      # expects, dropping nulls.
      renderValue = value: if lib.isBool value then lib.boolToString value else toString value;

      renderSettings =
        settings: lib.mapAttrs (_: renderValue) (lib.filterAttrs (_: v: v != null) settings);

      settingsType = lib.types.attrsOf (
        lib.types.nullOr (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.bool
          ]
        )
      );
    in
    {
      options.services.romm = {
        enable = lib.mkEnableOption "RomM, a self-hosted ROM manager and player";

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.romm;
          defaultText = lib.literalExpression "pkgs.romm";
          description = "The RomM package to run.";
        };

        rahasher = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.rahasher;
          defaultText = lib.literalExpression "pkgs.rahasher";
          description = ''
            RAHasher package providing the `RAHasher` binary used to compute
            RetroAchievements hashes. Set to `null` to disable (RA hashing is
            optional).
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Host port to expose the RomM web UI on.";
        };

        gunicornSocket = lib.mkOption {
          type = lib.types.path;
          default = "/run/romm/gunicorn.sock";
          readOnly = true;
          description = ''
            Path of the Unix socket the backend's gunicorn server listens on.
            Read-only; exposed so an external reverse proxy can be pointed at it
            when {option}`services.romm.nginx.enable` is `false`.
          '';
        };

        nginx.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to configure `services.nginx` to serve the RomM frontend and
            reverse-proxy the backend. The required `njs` and `mod_zip` modules
            are added via {option}`services.nginx.additionalModules`.

            Disable to run your own reverse proxy in front of the backend's
            gunicorn socket ({option}`services.romm.gunicornSocket`).
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to open the firewall for RomM's port.";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/romm";
          description = "Base directory for RomM persistent data (resources, assets, config, redis).";
        };

        libraryDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/romm/library";
          description = ''
            Directory containing ROMs and BIOS files.
            See <https://docs.romm.app/latest/getting-started/folder-structure/> for the expected layout.
          '';
        };

        baseUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://0.0.0.0";
          description = "Public URL of this RomM instance (ROMM_BASE_URL).";
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "DEBUG"
            "INFO"
            "WARNING"
            "ERROR"
            "CRITICAL"
          ];
          default = "INFO";
          description = "Application log level (LOGLEVEL).";
        };

        # RomM does not ship a database; consumers bring their own (a native
        # NixOS database service or an external host). These options describe how
        # RomM connects to it. The password is a secret and must be supplied via
        # `environmentFiles` as `DB_PASSWD`.
        database = {
          driver = lib.mkOption {
            type = lib.types.enum [
              "mariadb"
              "mysql"
              "postgresql"
            ];
            default = "mariadb";
            description = "Database driver RomM connects with (ROMM_DB_DRIVER).";
          };

          host = lib.mkOption {
            type = lib.types.str;
            example = "romm-db";
            description = "Host name of the database RomM connects to (DB_HOST).";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = if cfg.database.driver == "postgresql" then 5432 else 3306;
            defaultText = lib.literalExpression ''if driver == "postgresql" then 5432 else 3306'';
            description = "Port of the database RomM connects to (DB_PORT).";
          };

          name = lib.mkOption {
            type = lib.types.str;
            default = "romm";
            description = "Database name RomM connects to (DB_NAME).";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "romm";
            description = "Database user RomM connects as (DB_USER).";
          };
        };

        settings = lib.mkOption {
          type = settingsType;
          default = { };
          apply = renderSettings;
          example = lib.literalExpression ''
            {
              HASHEOUS_API_ENABLED = true;
              WEB_SERVER_CONCURRENCY = 4;
            }
          '';
          description = ''
            Environment variables for the RomM application, merged
            over the module-managed defaults. Any variable documented at
            <https://docs.romm.app/latest/reference/environment-variables/>
            may be set here.

            Do not put secrets here (they would land in the world-readable Nix
            store). Use {option}`services.romm.environmentFiles` instead.
          '';
        };

        environmentFiles = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          example = lib.literalExpression ''[ config.sops.secrets."romm/app-env".path ]'';
          description = ''
            Environment files for the RomM service. Must define
            the application secrets:
            - `DB_PASSWD` (must match the database user's password)
            - `ROMM_AUTH_SECRET_KEY` (generate with `openssl rand -hex 32`)

            Optionally, metadata provider credentials such as
            `IGDB_CLIENT_ID`/`IGDB_CLIENT_SECRET`, `STEAMGRIDDB_API_KEY`,
            `SCREENSCRAPER_USER`/`SCREENSCRAPER_PASSWORD`, etc.

            Provide these via a secrets manager (e.g. sops-nix) so they are
            never written to the Nix store.
          '';
        };

        metadataProviders = {
          hasheous.enable = lib.mkEnableOption "the Hasheous metadata provider (HASHEOUS_API_ENABLED)";
          launchbox.enable = lib.mkEnableOption "the LaunchBox metadata provider (LAUNCHBOX_API_ENABLED)";
          playmatch.enable = lib.mkEnableOption "the PlayMatch metadata provider (PLAYMATCH_API_ENABLED)";
          flashpoint.enable = lib.mkEnableOption "the Flashpoint metadata provider (FLASHPOINT_API_ENABLED)";
          hltb.enable = lib.mkEnableOption "the HowLongToBeat metadata provider (HLTB_API_ENABLED)";
          tgdb.enable = lib.mkEnableOption "the TheGamesDB metadata provider (TGDB_API_ENABLED)";

          retroachievements.cacheRefreshDays = lib.mkOption {
            type = lib.types.ints.positive;
            default = 30;
            description = ''
              RetroAchievements metadata cache refresh interval in days
              (REFRESH_RETROACHIEVEMENTS_CACHE_DAYS).

              The RetroAchievements API key is a secret; set
              `RETROACHIEVEMENTS_API_KEY` in
              {option}`services.romm.environmentFiles`.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.romm.settings = {
          ROMM_BASE_URL = lib.mkDefault cfg.baseUrl;
          ROMM_DB_DRIVER = lib.mkDefault cfg.database.driver;
          DB_HOST = lib.mkDefault cfg.database.host;
          DB_PORT = lib.mkDefault cfg.database.port;
          DB_NAME = lib.mkDefault cfg.database.name;
          DB_USER = lib.mkDefault cfg.database.user;
          LOGLEVEL = lib.mkDefault cfg.logLevel;

          ROMM_BASE_PATH = lib.mkDefault cfg.dataDir;
          REDIS_HOST = lib.mkDefault "127.0.0.1";
          REDIS_PORT = lib.mkDefault redisPort;
          GUNICORN_SOCKET = lib.mkDefault cfg.gunicornSocket;

          HASHEOUS_API_ENABLED = lib.mkDefault cfg.metadataProviders.hasheous.enable;
          LAUNCHBOX_API_ENABLED = lib.mkDefault cfg.metadataProviders.launchbox.enable;
          PLAYMATCH_API_ENABLED = lib.mkDefault cfg.metadataProviders.playmatch.enable;
          FLASHPOINT_API_ENABLED = lib.mkDefault cfg.metadataProviders.flashpoint.enable;
          HLTB_API_ENABLED = lib.mkDefault cfg.metadataProviders.hltb.enable;
          TGDB_API_ENABLED = lib.mkDefault cfg.metadataProviders.tgdb.enable;
          REFRESH_RETROACHIEVEMENTS_CACHE_DAYS = lib.mkDefault cfg.metadataProviders.retroachievements.cacheRefreshDays;
        };

        users.users.romm = {
          isSystemUser = true;
          group = "romm";
          home = cfg.dataDir;
        };
        users.groups.romm = { };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 romm romm -"
          "d ${cfg.dataDir}/resources 0750 romm romm -"
          "d ${cfg.dataDir}/assets 0750 romm romm -"
          "d ${cfg.dataDir}/config 0750 romm romm -"
          "d ${cfg.libraryDir} 0750 romm romm -"
        ];

        services.redis.servers.romm = {
          enable = true;
          user = "romm";
          port = redisPort;
          bind = "127.0.0.1";
        };

        systemd.services.romm = {
          description = "RomM, a self-hosted ROM manager and player";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "redis-romm.service"
          ];
          requires = [ "redis-romm.service" ];
          environment = cfg.settings;
          path = lib.optional (cfg.rahasher != null) cfg.rahasher;
          serviceConfig = {
            ExecStart = lib.getExe cfg.package;
            User = "romm";
            Group = "romm";
            EnvironmentFile = cfg.environmentFiles;
            RuntimeDirectory = "romm";
            RuntimeDirectoryMode = "0750";
            UMask = "0007";
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        # njs backs the internal `/decode` route; mod_zip (nginxModules.zip)
        # backs streamed multi-file ROM downloads.
        users.users.${config.services.nginx.user}.extraGroups = lib.mkIf cfg.nginx.enable [ "romm" ];

        services.nginx = lib.mkIf cfg.nginx.enable {
          enable = true;
          additionalModules = [
            pkgs.nginxModules.njs
            pkgs.nginxModules.zip
          ];
          commonHttpConfig = ''
            js_import decode from ${decodeJs};
            upstream romm_wsgi_server {
              server unix:${cfg.gunicornSocket};
            }
            map $http_x_forwarded_proto $forwardscheme {
              default $scheme;
              https https;
            }
            # COEP/COOP for the EmulatorJS player path, enabling SharedArrayBuffer
            # (needed for multi-threaded cores).
            map $request_uri $coep_header {
              default        "";
              ~^/rom/.*/ejs$ "require-corp";
            }
            map $request_uri $coop_header {
              default        "";
              ~^/rom/.*/ejs$ "same-origin";
            }
          '';
          virtualHosts."romm" = {
            listen = [
              {
                addr = "0.0.0.0";
                inherit (cfg) port;
              }
            ];
            root = "${cfg.package.frontend}";
            locations = {
              "/" = {
                tryFiles = "$uri $uri/ /index.html";
                extraConfig = ''
                  proxy_redirect off;
                  add_header Access-Control-Allow-Origin *;
                  add_header Access-Control-Allow-Methods *;
                  add_header Access-Control-Allow-Headers *;
                  add_header Cross-Origin-Embedder-Policy $coep_header;
                  add_header Cross-Origin-Opener-Policy $coop_header;
                '';
              };
              "/assets" = {
                tryFiles = "$uri $uri/ =404";
              };
              "/assets/romm/resources/" = {
                alias = "${cfg.dataDir}/resources/";
                tryFiles = "$uri $uri/ =404";
              };
              "/openapi.json".proxyPass = "http://romm_wsgi_server";
              "/api" = {
                proxyPass = "http://romm_wsgi_server";
                extraConfig = ''
                  proxy_request_buffering off;
                  proxy_buffering off;
                  proxy_read_timeout 300s;
                '';
              };
              "~ ^/(ws|netplay)" = {
                proxyPass = "http://romm_wsgi_server";
                proxyWebsockets = true;
              };
              "/library/" = {
                extraConfig = ''
                  internal;
                  alias ${cfg.libraryDir}/;
                '';
              };
              "/decode" = {
                extraConfig = ''
                  internal;
                  js_content decode.decodeBase64;
                '';
              };
            };
            extraConfig = ''
              client_max_body_size 0;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $forwardscheme;
            '';
          };
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };

  moduleTests =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.romm;
    in
    {
      tests."romm/http" = lib.mkIf cfg.enable (
        lib.addMetaAttrs
          {
            description = "Verify RomM starts against an external database and serves HTTP";
          }
          (
            pkgs.testers.runNixOSTest {
              name = "romm";
              globalTimeout = 60 * 3;
              extraBaseModules.imports = [ module ];

              nodes.server =
                { pkgs, ... }:
                {
                  virtualisation.diskSize = 1024 * 4;

                  # Bring-your-own database: a native MariaDB on the host.
                  services.mysql = {
                    enable = true;
                    package = pkgs.mariadb;
                    initialDatabases = [ { name = "romm"; } ];
                    initialScript = pkgs.writeText "romm-db-init" ''
                      CREATE USER IF NOT EXISTS 'romm'@'%' IDENTIFIED BY 'testpassword';
                      GRANT ALL PRIVILEGES ON romm.* TO 'romm'@'%';
                      FLUSH PRIVILEGES;
                    '';
                  };

                  services.romm = {
                    enable = true;
                    database.host = "127.0.0.1";
                    environmentFiles = [
                      (pkgs.writeText "romm-app-env" ''
                        DB_PASSWD=testpassword
                        ROMM_AUTH_SECRET_KEY=0000000000000000000000000000000000000000000000000000000000000000
                      '')
                    ];
                  };
                };

              testScript = ''
                server.wait_for_unit("mysql.service", timeout=90)
                server.wait_for_open_port(3306, timeout=90)
                server.wait_for_unit("redis-romm.service", timeout=90)
                server.wait_for_unit("romm.service", timeout=120)
                server.wait_for_unit("nginx.service", timeout=90)
                server.wait_for_open_port(8080, timeout=120)
                server.succeed("curl -sf http://localhost:8080")
              '';
            }
          )
      );

      tests."romm/postgresql" = lib.mkIf cfg.enable (
        lib.addMetaAttrs
          {
            description = "Verify RomM starts against a native PostgreSQL database and serves HTTP";
          }
          (
            pkgs.testers.runNixOSTest {
              name = "romm-postgresql";
              globalTimeout = 60 * 5;
              extraBaseModules.imports = [ module ];

              nodes.server =
                { config, pkgs, ... }:
                {
                  virtualisation.diskSize = 1024 * 4;

                  services.postgresql = {
                    enable = true;
                    ensureDatabases = [ "romm" ];
                    ensureUsers = [
                      {
                        name = "romm";
                        ensureDBOwnership = true;
                      }
                    ];
                    authentication = lib.mkAfter ''
                      host romm romm 127.0.0.1/32 scram-sha-256
                      host romm romm ::1/128 scram-sha-256
                    '';
                  };

                  systemd.services.romm-db-password = {
                    description = "Set the RomM PostgreSQL role password";
                    after = [ "postgresql.service" ];
                    requires = [ "postgresql.service" ];
                    wantedBy = [ "multi-user.target" ];
                    before = [ "romm.service" ];
                    requiredBy = [ "romm.service" ];
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      User = "postgres";
                    };
                    script = ''
                      ${config.services.postgresql.package}/bin/psql --no-psqlrc --set ON_ERROR_STOP=1 <<SQL
                      ALTER ROLE romm WITH PASSWORD 'testpassword';
                      SQL
                    '';
                  };

                  services.romm = {
                    enable = true;
                    database = {
                      driver = "postgresql";
                      host = "127.0.0.1";
                    };
                    environmentFiles = [
                      (pkgs.writeText "romm-app-env" ''
                        DB_PASSWD=testpassword
                        ROMM_AUTH_SECRET_KEY=0000000000000000000000000000000000000000000000000000000000000000
                      '')
                    ];
                  };
                };

              testScript = ''
                server.wait_for_unit("postgresql.service", timeout=120)
                server.wait_for_unit("romm-db-password.service", timeout=120)
                server.wait_for_unit("romm.service", timeout=180)
                server.wait_for_open_port(8080, timeout=180)
                # RomM only serves successfully once it has connected to and migrated the
                # database, so a healthy HTTP response exercises the full DB path.
                server.wait_until_succeeds("curl -sf http://localhost:8080", timeout=180)
              '';
            }
          )
      );
    };
in
{
  imports = [
    module
    moduleTests
  ];
}
