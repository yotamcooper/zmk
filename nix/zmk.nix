{ stdenvNoCC, lib, buildPackages
, cmake, ninja, dtc, gcc-arm-embedded
, zephyr
, board ? "glove80_lh"
, shield ? null
, keymap ? null
, kconfig ? null
, overlay ? null
, extraModules ? []
, snippets ? []
}:


let
  # from zephyr/scripts/requirements-base.txt
  packageOverrides = pyself: pysuper: {
    can = pysuper.can.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
    });

    canopen = pysuper.can.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
    });
  };

  python = (buildPackages.python3.override { inherit packageOverrides; }).withPackages (ps: with ps; [
    pyelftools
    pyyaml
    canopen
    packaging
    progress
    anytree
    intelhex
    pykwalify
  ]);

  requiredZephyrModules = [
    "cmsis" "hal_nordic" "tinycrypt" "lvgl" "picolibc" "segger" "cirque-input-module"
  ];

  directZephyrModules = [ "cirque-input-module" ];

  zephyrModuleDeps =
    let modules = lib.attrVals requiredZephyrModules zephyr.modules;
    in map (x: if builtins.elem x.src.name directZephyrModules then x.src else x.modulePath) modules;
in

stdenvNoCC.mkDerivation {
  name = "zmk_${board}";

  sourceRoot = "source/app";

  src = builtins.path {
    name = "source";
    path = ./..;
    filter = path: type:
      let relPath = lib.removePrefix (toString ./.. + "/") (toString path);
      in (lib.cleanSourceFilter path type) && ! (
        relPath == "nix" || lib.hasSuffix ".nix" path ||
        relPath == "build" || relPath == ".west" ||
        relPath == "modules" || relPath == "tools" || relPath == "zephyr" ||
        relPath == "lambda" || relPath == ".github"
      );
    };

  preConfigure = ''
    cmakeFlagsArray+=("-DUSER_CACHE_DIR=$TEMPDIR/.cache")
  '';

  cmakeFlags = [
    "-DZEPHYR_BASE=${zephyr}/zephyr"
    "-DBOARD_ROOT=."
    "-DBOARD=${board}"
    "-DZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb"
    "-DGNUARMEMB_TOOLCHAIN_PATH=${gcc-arm-embedded}"
    "-DCMAKE_C_COMPILER=${gcc-arm-embedded}/bin/arm-none-eabi-gcc"
    "-DCMAKE_CXX_COMPILER=${gcc-arm-embedded}/bin/arm-none-eabi-g++"
    "-DCMAKE_AR=${gcc-arm-embedded}/bin/arm-none-eabi-ar"
    "-DCMAKE_RANLIB=${gcc-arm-embedded}/bin/arm-none-eabi-ranlib"
    "-DZEPHYR_MODULES=${lib.concatStringsSep ";" zephyrModuleDeps}"
  ] ++
  (lib.optional (shield != null) "-DSHIELD=${shield}") ++
  (lib.optional (keymap != null) "-DKEYMAP_FILE=${keymap}") ++
  (lib.optional (kconfig != null) "-DEXTRA_CONF_FILE=${kconfig}") ++
  (lib.optional (overlay != null) "-DDTC_OVERLAY_FILE=${overlay}") ++
  (lib.optional (extraModules != []) "-DZMK_EXTRA_MODULES=${lib.concatStringsSep ";" extraModules}") ++
  (lib.optional (snippets != []) "-DSNIPPET=${lib.concatStringsSep ";" snippets}");

  nativeBuildInputs = [ cmake ninja python dtc gcc-arm-embedded ];
  buildInputs = [ zephyr ];

  installPhase = ''
    mkdir $out
    cp zephyr/zmk.{uf2,hex,bin,elf} $out
    cp zephyr/.config $out/zmk.kconfig
    cp zephyr/zephyr.dts $out/zmk.dts
  '';

  passthru = { inherit zephyrModuleDeps; };
}
