final: prev: {
  github-copilot-cli =
    if prev.stdenv.hostPlatform.system == "aarch64-darwin" then
      final.callPackage ../pkgs/github-copilot-cli-prebuilt.nix { }
    else
      prev.github-copilot-cli;
}
