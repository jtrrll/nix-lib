{
  config.perSystem = _: {
    config.files = {
      file."LICENSE".text = builtins.readFile ./agpl_3.0.txt;
      writer.app = true;
    };
  };
}
