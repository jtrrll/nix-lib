{ lib }:
let
  inherit (import ./strings.nix { inherit lib; }) snakeToCamel;
in
{
  snakeToCamel = {
    testEmpty = {
      expr = snakeToCamel "";
      expected = "";
    };
    testSingleWord = {
      expr = snakeToCamel "foo";
      expected = "foo";
    };
    testTwoWords = {
      expr = snakeToCamel "foo_bar";
      expected = "fooBar";
    };
    testManyWords = {
      expr = snakeToCamel "foo_bar_baz";
      expected = "fooBarBaz";
    };
    testSingleLetters = {
      expr = snakeToCamel "a_b_c";
      expected = "aBC";
    };
    testLeadingUnderscore = {
      expr = snakeToCamel "_foo_bar";
      expected = "FooBar";
    };
    testTrailingUnderscore = {
      expr = snakeToCamel "foo_bar_";
      expected = "fooBar";
    };
    testConsecutiveUnderscores = {
      expr = snakeToCamel "foo__bar";
      expected = "fooBar";
    };
  };
}
