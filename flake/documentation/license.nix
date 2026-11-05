{
  config.perSystem = { lib, ... }: {
    config.files = {
      file."LICENSE".text = lib.readFile ./agpl_3.0.txt;
      writer.app = true;
    };
  };
}
