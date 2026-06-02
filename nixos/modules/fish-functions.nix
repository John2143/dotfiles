{
  pkgs,
  lib,
  ...
}:
let
  inherit (builtins) readDir readFile;
  inherit (lib) hasSuffix hasPrefix removeSuffix removePrefix filterAttrs attrNames;
  inherit (lib.strings) trim splitString;

  fishDir = ./../../fish_functions;
  entries = readDir fishDir; # { name = "regular"|"directory"; ... }

  # All regular .fish files
  allFiles = filterAttrs (n: t: t == "regular" && hasSuffix ".fish" n) entries;

  # Split into cross-platform and Linux-only
  linuxFiles = filterAttrs (n: t: hasSuffix ".linux.fish" n) allFiles;
  commonFiles = filterAttrs (n: t: !hasSuffix ".linux.fish" n) allFiles;

  # Extract the function name from filename
  funcName = name:
    if hasSuffix ".linux.fish" name then
      removeSuffix ".linux.fish" name
    else
      removeSuffix ".fish" name;

  # Read a single .fish file and extract metadata
  loadFile = name: let
    path = fishDir + "/${name}";
    content = readFile path;
    fname = funcName name;
    lines = splitString "\n" content;

    # Find the first # DESCRIPTION: line
    descLine = lib.findFirst
      (l: hasPrefix "# DESCRIPTION:" (trim l))
      null
      lines;

    description =
      if descLine != null then
        trim (removePrefix "# DESCRIPTION:" (trim descLine))
      else
        "Fish function ${fname}";

    # Strip metadata comment lines from the body
    bodyLines = builtins.filter (
      l: !hasPrefix "# DESCRIPTION:" (trim l)
    ) lines;

    body = lib.concatStringsSep "\n" bodyLines;
  in {
    name = fname;
    value = {
      inherit body description;
    };
  };

  commonFuncs = builtins.listToAttrs (map loadFile (attrNames commonFiles));
  linuxFuncs = builtins.listToAttrs (map loadFile (attrNames linuxFiles));
in {
  programs.fish.functions = commonFuncs // lib.optionalAttrs pkgs.stdenv.isLinux linuxFuncs;
}
