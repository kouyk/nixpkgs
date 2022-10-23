{ delve, autoPatchelfHook, stdenv, patchelf, glibc, gcc-unwrapped }:
# This is a list of plugins that need special treatment. For example, the go plugin (id is 9568) comes with delve, a
# debugger, but that needs various linking fixes. The changes here replace it with the system one.
{
  "631" = { # Python
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
  };
  "7322" = {  # Python community edition
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
  };
  "7495" = { # .ignore
    buildPhase = ''
      echo "Due to the unpacked directory starting with a `.`, this plugin won't work until #191355 is merged."
      exit 1
      '';
  };
  "8182" = { # Rust
    nativeBuildInputs = [ autoPatchelfHook ];
    commands = "chmod +x -R bin";
  };
  "9568" = {  # Go
    buildInputs = [ delve ];
    commands = let
      arch = (if stdenv.isLinux then "linux" else "mac") + (if stdenv.isAarch64 then "arm" else "");
    in "ln -sf ${delve}/bin/dlv lib/dlv/${arch}/dlv";
  };
  "17718" = {
    nativeBuildInputs = [ patchelf ];
    buildInputs = [ glibc gcc-unwrapped ];
    commands = let
      libPath = prev.lib.makeLibraryPath [pkgs-jb-plugins.glibc pkgs-jb-plugins.gcc-unwrapped];
      in ''
        agent="copilot-agent/bin/copilot-agent-linux"
        orig_size=$(stat --printf=%s $agent)
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" $agent
        patchelf --set-rpath ${libPath} $agent
        chmod +x $agent
        new_size=$(stat --printf=%s $agent)
        # https://github.com/NixOS/nixpkgs/pull/48193/files#diff-329ce6280c48eac47275b02077a2fc62R25
        ###### zeit-pkg fixing starts here.
        # we're replacing plaintext js code that looks like
        # PAYLOAD_POSITION = '1234                  ' | 0
        # [...]
        # PRELUDE_POSITION = '1234                  ' | 0
        # ^-----20-chars-----^^------22-chars------^
        # ^-- grep points here
        #
        # var_* are as described above
        # shift_by seems to be safe so long as all patchelf adjustments occur
        # before any locations pointed to by hardcoded offsets
        var_skip=20
        var_select=22
        shift_by=$(expr $new_size - $orig_size)
        function fix_offset {
          # $1 = name of variable to adjust
          location=$(grep -obUam1 "$1" $agent | cut -d: -f1)
          location=$(expr $location + $var_skip)
          value=$(dd if=$agent iflag=count_bytes,skip_bytes skip=$location \
            bs=1 count=$var_select status=none)
          value=$(expr $shift_by + $value)
          echo -n $value | dd of=$agent bs=1 seek=$location conv=notrunc
        }
        fix_offset PAYLOAD_POSITION
        fix_offset PRELUDE_POSITION
      '';
  };
}
