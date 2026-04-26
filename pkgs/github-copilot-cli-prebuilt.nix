{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  bash,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "github-copilot-cli";
  version = "1.0.36";

  src = fetchurl {
    url = "https://github.com/github/copilot-cli/releases/download/v${finalAttrs.version}/copilot-darwin-arm64.tar.gz";
    hash = "sha256-KI7giLtXw4UwiRR/fcfvfR7Mpffy+e5hPxNlIy4nehk=";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];
  sourceRoot = ".";
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 copilot $out/libexec/copilot
    runHook postInstall
  '';

  postInstall = ''
    makeWrapper $out/libexec/copilot $out/bin/copilot \
      --add-flags "--no-auto-update" \
      --prefix PATH : "${lib.makeBinPath [ bash ]}"
  '';

  meta = {
    description = "GitHub Copilot CLI";
    homepage = "https://github.com/github/copilot-cli";
    changelog = "https://github.com/github/copilot-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.unfree;
    mainProgram = "copilot";
    platforms = [ "aarch64-darwin" ];
  };
})
