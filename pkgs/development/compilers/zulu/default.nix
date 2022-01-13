{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, unzip
, makeWrapper
, setJavaClassPath
, zulu
# minimum dependencies
, alsa-lib
, fontconfig
, freetype
, zlib
, xorg
# runtime dependencies
, cups
# runtime dependencies for GTK+ Look and Feel
, gtkSupport ? stdenv.isLinux
, cairo
, glib
, gtk3
, enableJavaFX ? false
}:

let
  version = "11.50.19";
  openjdk = "11.0.12";

  sha256_linux = if enableJavaFX 
    then "9cda7eeb8dfb253d9a50eac688bc0cd7b296ef9aede7c55b9a53320566376d34" 
    else "b8e8a63b79bc312aa90f3558edbea59e71495ef1a9c340e38900dd28a1c579f3";
  sha256_darwin = if enableJavaFX 
    then "96fba96ca0279add13bda61c56b717949431eece9f53731df83962b1d29f3098"
    else "9bc6874932f7f88d0a48220d3200449ddf7dc5c0e82af2df2738bc13d21b0e4e";

  platform = if stdenv.isDarwin then "macosx" else "linux";
  hash = if stdenv.isDarwin then sha256_darwin else sha256_linux;
  extension = if stdenv.isDarwin then "zip" else "tar.gz";
  fx = if enableJavaFX then "-fx" else "";

  runtimeDependencies = [
    cups
  ] ++ lib.optionals gtkSupport [
    cairo glib gtk3
  ];
  runtimeLibraryPath = lib.makeLibraryPath runtimeDependencies;

in stdenv.mkDerivation {
  inherit version openjdk platform hash extension fx;

  pname = "zulu";

  src = fetchurl {
    url = "https://cdn.azul.com/zulu/bin/zulu${version}-ca${fx}-jdk${openjdk}-${platform}_x64.${extension}";
    sha256 = hash;
  };

  buildInputs = lib.optionals stdenv.isLinux [
    alsa-lib # libasound.so wanted by lib/libjsound.so
    fontconfig
    freetype
    stdenv.cc.cc # libstdc++.so.6
    xorg.libX11
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    zlib
  ];

  nativeBuildInputs = [
    autoPatchelfHook makeWrapper
  ] ++ lib.optionals stdenv.isDarwin [
    unzip
  ];

  installPhase = ''
    mkdir -p $out
    cp -r ./* "$out/"
  '' + lib.optionalString stdenv.isLinux ''
    # jni.h expects jni_md.h to be in the header search path.
    ln -s $out/include/linux/*_md.h $out/include/
  '' + ''
    mkdir -p $out/nix-support
    printWords ${setJavaClassPath} > $out/nix-support/propagated-build-inputs

    # Set JAVA_HOME automatically.
    cat <<EOF >> $out/nix-support/setup-hook
    if [ -z "\''${JAVA_HOME-}" ]; then export JAVA_HOME=$out; fi
    EOF
  '' + lib.optionalString stdenv.isLinux ''
    # We cannot use -exec since wrapProgram is a function but not a command.
    #
    # jspawnhelper is executed from JVM, so it doesn't need to wrap it, and it
    # breaks building OpenJDK (#114495).
    for bin in $( find "$out" -executable -type f -not -name jspawnhelper ); do
      wrapProgram "$bin" --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}"
    done
  '';

  preFixup = ''
    find "$out" -name libfontmanager.so -exec \
      patchelf --add-needed libfontconfig.so {} \;
  '';

  passthru = {
    home = zulu;
  };

  meta = with lib; {
    homepage = "https://www.azul.com/products/zulu/";
    license = licenses.gpl2;
    description = "Certified builds of OpenJDK";
    longDescription = ''
      Certified builds of OpenJDK that can be deployed across multiple
      operating systems, containers, hypervisors and Cloud platforms.
    '';
    maintainers = with maintainers; [ fpletz ];
    platforms = [ "x86_64-linux" "x86_64-darwin" ];
    mainProgram = "java";
  };
}
