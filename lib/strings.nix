{ lib }:
{
  snakeToCamel =
    s:
    lib.pipe s [
      (lib.splitString "_")
      (lib.imap0 (
        i: part: if i == 0 then part else lib.toUpper (lib.substring 0 1 part) + lib.substring 1 (-1) part
      ))
      lib.concatStrings
    ];
}
