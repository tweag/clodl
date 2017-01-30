import Data.Monoid
import Distribution.Simple
import System.Directory (getCurrentDirectory, withCurrentDirectory)
import System.Process (system)
import System.Exit
import System.FilePath ((</>))

main = defaultMainWithHooks simpleUserHooks
    { postConf = \_ _ _ _ -> configurePatchElf
    , postBuild = \_ _ _ _ -> do
        buildJavaSource
        buildPatchElf
    }

configurePatchElf = do
    withCurrentDirectory "vendor/patchelf" $
      executeShellCommand "./bootstrap.sh"
    cwd <- getCurrentDirectory
    executeShellCommand "mkdir -p build/src/patchelf"
    withCurrentDirectory "build/src/patchelf" $
      executeShellCommand $
        cwd </> "vendor/patchelf/configure --prefix=" <>
        cwd </> "build"

buildJavaSource = do
    executeShellCommand "gradle build"

buildPatchElf = do
    withCurrentDirectory "build/src/patchelf" $
      executeShellCommand "make install"

executeShellCommand cmd = system cmd >>= check
  where
    check ExitSuccess = return ()
    check (ExitFailure n) =
        error $ "Command " ++ cmd ++ " exited with failure code " ++ show n
