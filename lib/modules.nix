{ lib }:
let
  nixFilesInDir =
    {
      path,
      recurse ? false,
    }:
    lib.concatLists (
      lib.mapAttrsToList (
        name: kind:
        let
          entry = path + "/${name}";
        in
        if kind == "directory" then
          (
            if recurse then
              nixFilesInDir {
                path = entry;
                inherit recurse;
              }
            else
              [ ]
          )
        else if kind == "regular" && lib.hasSuffix ".nix" name then
          [ entry ]
        else
          [ ]
      ) (builtins.readDir path)
    );
in
{
  inherit nixFilesInDir;

  aggregate = modules: modules // { default.imports = lib.attrValues modules; };

  modulesByClassAndName =
    {
      path,
      transform ? (
        class: name: module: {
          inherit class name module;
        }
      ),
    }:
    let
      entriesForClass =
        className:
        lib.mapAttrsToList (
          entryName: kind:
          let
            entryPath = path + "/${className}/${entryName}";
            module = {
              _file = toString entryPath;
              imports =
                if kind == "directory" then
                  nixFilesInDir {
                    path = entryPath;
                    recurse = true;
                  }
                else
                  [ entryPath ];
            };
            result = transform className (lib.removeSuffix ".nix" entryName) module;
          in
          {
            inherit (result) class name;
            module = {
              _class = result.class;
            }
            // result.module;
          }
        ) (builtins.readDir (path + "/${className}"));
    in
    lib.pipe path [
      (p: if builtins.pathExists p then builtins.readDir p else { })
      (lib.filterAttrs (_: kind: kind == "directory"))
      lib.attrNames
      (lib.concatMap entriesForClass)
      (lib.foldl' (
        acc: entry: lib.recursiveUpdate acc { ${entry.class}.${entry.name} = entry.module; }
      ) { })
    ];
}
