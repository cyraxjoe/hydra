{ hydraSrc ? { outPath = ./.; revCount = 1234; rev = "abcdef"; }
, nixpkgs ? <nixpkgs>
, system ? "x86_64-linux"
}:
let
  pkgs = import nixpkgs { };

  version = builtins.readFile ./version + "." + toString hydraSrc.revCount + "." + hydraSrc.rev;
in
with pkgs;
rec {
  build =  
    let
      aws-sdk-cpp' =
        aws-sdk-cpp.override {
          apis = ["s3"];
          customMemoryManagement = false;
        };

      nix = nixUnstable;

      perlDeps = buildEnv {
        name = "hydra-perl-deps";

        paths = with perlPackages;
          [ ModulePluggable
            CatalystActionREST
            CatalystAuthenticationStoreDBIxClass
            CatalystDevel
            CatalystDispatchTypeRegex
            CatalystPluginAccessLog
            CatalystPluginAuthorizationRoles
            CatalystPluginCaptcha
            CatalystPluginSessionStateCookie
            CatalystPluginSessionStoreFastMmap
            CatalystPluginStackTrace
            CatalystPluginUnicodeEncoding
            CatalystTraitForRequestProxyBase
            CatalystViewDownload
            CatalystViewJSON
            CatalystViewTT
            CatalystXScriptServerStarman
            CryptRandPasswd
            DBDPg
            DBDSQLite
            DataDump
            DateTime
            DigestSHA1
            EmailMIME
            EmailSender
            FileSlurp
            IOCompress
            IPCRun
            JSONXS
            LWP
            LWPProtocolHttps
            NetAmazonS3
            NetStatsd
            PadWalker
            Readonly
            SQLSplitStatement
            SetScalar
            Starman
            SysHostnameLong
            TestMore
            TextDiff
            TextTable
            XMLSimple
            nix
            nix.perl-bindings
            git
            boehmgc
            aws-sdk-cpp'
          ];
      };
    in
    releaseTools.nixBuild {
      name = "hydra-${version}";

      src = hydraSrc;

      stdenv = overrideCC stdenv gcc6;

      buildInputs =
        [ makeWrapper autoconf automake libtool unzip nukeReferences pkgconfig sqlite libpqxx
          gitAndTools.topGit mercurial darcs subversion bazaar openssl bzip2 libxslt
          guile # optional, for Guile + Guix support
          perlDeps perl nix
        ];

      hydraPath = lib.makeBinPath (
        [ sqlite subversion openssh nix coreutils findutils pixz
          gzip bzip2 lzma gnutar unzip git gitAndTools.topGit mercurial darcs gnused bazaar
        ] ++ lib.optionals stdenv.isLinux [ rpm dpkg cdrkit ] );

      postUnpack = ''
        # Clean up when building from a working tree.
        (cd $sourceRoot && (git ls-files -o --directory | xargs -r rm -rfv)) || true
      '';

      configureFlags = [ "--with-docbook-xsl=${docbook_xsl}/xml/xsl/docbook" ];

      shellHook = ''
        PATH=$(pwd)/src/hydra-evaluator:$(pwd)/src/script:$(pwd)/src/hydra-eval-jobs:$(pwd)/src/hydra-queue-runner:$PATH
      '';

      preConfigure = "autoreconf -vfi";

      enableParallelBuilding = true;

      preCheck = ''
        patchShebangs .
        export LOGNAME=''${LOGNAME:-foo}
      '';

      postInstall = ''
        mkdir -p $out/nix-support

        for i in $out/bin/*; do
            read -n 4 chars < $i
            if [[ $chars =~ ELF ]]; then continue; fi
            wrapProgram $i \
                --prefix PERL5LIB ':' $out/libexec/hydra/lib:$PERL5LIB \
                --prefix PATH ':' $out/bin:$hydraPath \
                --set HYDRA_RELEASE ${version} \
                --set HYDRA_HOME $out/libexec/hydra \
                --set NIX_RELEASE ${nix.name or "unknown"}
        done
      ''; # */

      dontStrip = true;

      meta.description = "Build of Hydra on ${system}";

      passthru.perlDeps = perlDeps;
    };

  manual = pkgs.runCommand "hydra-manual-${version}" { inherit build;  }
    ''
      mkdir -p $out/share
      cp -prvd $build/share/doc $out/share/

      mkdir $out/nix-support
      echo "doc manual $out/share/doc/hydra" >> $out/nix-support/hydra-build-products
    '';
}

