{
  description = "AltTab (personal fork) built with the host's Xcode";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      mkAltTab = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "johnnys-alt-tab";
        version = self.shortRev or self.dirtyShortRev or "dev";
        src = self;
        # xcodebuild and the SDK live outside the store (/Applications/Xcode.app), so this needs
        # `sandbox = false` or `sandbox = relaxed` in nix.conf.
        __noChroot = true;
        dontConfigure = true;
        dontFixup = true;
        buildPhase = ''
          runHook preBuild
          # Nix's darwin env vars (SDKROOT, DEVELOPER_DIR, deployment target, compiler wrappers)
          # override Xcode's own toolchain selection, so drop them and use the system Xcode.
          unset SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET NIX_CFLAGS_COMPILE NIX_LDFLAGS LD CC CXX
          export PATH=/usr/bin:/bin:/usr/sbin:/sbin
          # Xcode/SwiftPM resolve the home dir via Foundation (nixbld's is unwritable /var/empty),
          # which ignores $HOME but honours CFFIXED_USER_HOME.
          export HOME=$TMPDIR CFFIXED_USER_HOME=$TMPDIR
          # The nixbld user can't reach the login keychain's "Local Self-Signed" identity, so sign
          # ad-hoc. The signature then changes with every build, which resets TCC grants.
          # The versions normally come from the gitignored config/local.xcconfig, which isn't in the
          # flake source; without them Info.plist lacks CFBundleVersion and App.version crashes at launch.
          xcodebuild \
            -project alt-tab-macos.xcodeproj \
            -scheme Debug \
            -configuration Debug \
            -derivedDataPath "$TMPDIR/DerivedData" \
            -packageCachePath "$TMPDIR/spm-cache" \
            -clonedSourcePackagesDirPath "$TMPDIR/spm-packages" \
            CODE_SIGN_IDENTITY=- \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM= \
            CURRENT_PROJECT_VERSION=1 \
            MARKETING_VERSION=1.0
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications
          cp -R "$TMPDIR/DerivedData/Build/Products/Debug/AltTab.app" $out/Applications/
          runHook postInstall
        '';
        meta = {
          description = "Windows alt-tab on macOS";
          homepage = "https://github.com/jsnelgro/alt-tab-macos";
          license = pkgs.lib.licenses.gpl3Only;
          platforms = systems;
          mainProgram = "AltTab";
        };
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        johnnys-alt-tab = mkAltTab pkgs;
        default = johnnys-alt-tab;
      });
      overlays.default = final: _prev: { johnnys-alt-tab = mkAltTab final; };
    };
}
