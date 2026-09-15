{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.serviceStatus;
in
{
  options.services.serviceStatus = {
    enable = lib.mkEnableOption "HTTP server that reports managed background service status";
    port = lib.mkOption {
      type = lib.types.port;
      default = 5679;
      description = "Port to listen on.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      service-status = {
        enable = true;
        config = {
          ProgramArguments = [
            (lib.getExe pkgs.service-status)
            "--port"
            (builtins.toString cfg.port)
          ];
          KeepAlive = {
            Crashed = true;
            SuccessfulExit = false;
          };
          RunAtLoad = true;
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/service_status.err";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/service_status.log";
        };
      };
    };

    systemd.user.services = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
      service-status = {
        Service = {
          ExecStart = "${lib.getExe pkgs.service-status} --port ${builtins.toString cfg.port}";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
        Unit = {
          Description = "HTTP server that reports managed background service status";
          X-Restart-Triggers = [ (lib.getExe pkgs.service-status) ];
        };
      };
    };
  };
}
