import Data.Monoid
import Distribution.Simple
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.BuildPaths (mkSharedLibName)
import Distribution.Simple.Setup (buildVerbosity, configVerbosity, fromFlag)
import Distribution.Simple.Utils (rawSystemExit)
import System.Directory (getCurrentDirectory, withCurrentDirectory)
import System.Exit
import System.FilePath ((</>))

main = defaultMainWithHooks simpleUserHooks
    { postConf = \_ flags _ _ -> do
        let verbosity = fromFlag (configVerbosity flags)
        configurePatchElf verbosity
    , postBuild = \_ flags _ lbi -> do
        let verbosity = fromFlag (buildVerbosity flags)
        buildJavaSource verbosity
        buildPatchElf verbosity
    }

configurePatchElf verbosity = do
    print "################################################################################ patchelf"
    error
    withCurrentDirectory "vendor/patchelf" $
      rawSystemExit verbosity "./bootstrap.sh" []
    cwd <- getCurrentDirectory
    rawSystemExit verbosity "mkdir" ["-p", "build/src/patchelf"]
    withCurrentDirectory "build/src/patchelf" $
      rawSystemExit
        verbosity
        (cwd </> "vendor/patchelf/configure")
        ["--prefix=" <> cwd </> "build"]

buildJavaSource verbosity = do
    print "################################################################################ gradle"
    error
    rawSystemExit
      verbosity
      "gradle"
      ["build"]

buildPatchElf verbosity = do
    print "############################################################################# build patchelf"
    error
    withCurrentDirectory "build/src/patchelf" $
      rawSystemExit verbosity "make" ["install"]
