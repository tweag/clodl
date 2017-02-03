{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TupleSections #-}

module Main where

import Codec.Archive.Zip
  ( addEntryToArchive
  , emptyArchive
  , fromArchive
  , toArchive
  , toEntry
  )
import Control.Monad (unless)
import Data.Text (pack, strip, unpack)
import Data.List (intercalate, isInfixOf)
import qualified Data.ByteString.Lazy as BS
import Paths_jarify
import System.Directory (copyFile, doesFileExist)
import System.Environment (getArgs)
import System.FilePath ((</>), (<.>), isAbsolute, takeBaseName, takeFileName)
import System.Info (os)
import System.IO (hPutStrLn, stderr)
import System.IO.Temp (withSystemTempFile)
import System.Process (callProcess, readProcess)
import Text.Regex.TDFA

stripString :: String -> String
stripString = unpack . strip . pack

-- | Add @$ORIGIN@ to RPATH and dependency on @libHSjarify.so@.
patchElf :: FilePath -> IO ()
patchElf exe = do
    dyndir <- getDynLibDir
    rpath <- readProcess "patchelf" ["--print-rpath", exe] ""
    let newrpath = intercalate ":" ["$ORIGIN", dyndir, rpath]
    callProcess "patchelf" ["--set-rpath", newrpath, exe]

doPackage :: FilePath -> FilePath -> IO ()
doPackage baseJar cmd = do
    jarbytes <- BS.readFile baseJar
    cmdpath <- doesFileExist cmd >>= \case
      False -> stripString <$> readProcess "which" [cmd] ""
      True -> return cmd
    (hsapp, libs) <- withSystemTempFile "hsapp" $ \tmp _ -> do
      copyFile cmdpath tmp
      patchElf tmp
      ldd <- case os of
        "darwin" -> do
          hPutStrLn
            stderr
            "WARNING: JAR not self contained on OS X (shared libraries not copied)."
          return ""
        _ -> readProcess "ldd" [tmp] ""
      let unresolved =
            map fst $
            filter (not . isAbsolute . snd) $
            map (\xs -> (xs !! 1, xs !! 2)) (ldd =~ "(.+) => (.+)" :: [[String]])
          libs =
            filter (\x -> not $ any (`isInfixOf` x) ["libc.so", "libpthread.so"]) $
            map (!! 1) (ldd =~ " => (.*) \\(0x[0-9a-f]+\\)" :: [[String]])
      unless (null unresolved) $
        fail $
          "Unresolved libraries in " ++
          cmdpath ++
          ":\n" ++
          unlines unresolved
      (, libs) <$> BS.readFile tmp
    libentries <- mapM mkEntry libs
    let cmdentry = toEntry "hsapp" 0 hsapp
        appzip =
          toEntry "jarify-app.zip" 0 $
          fromArchive $
          foldr addEntryToArchive emptyArchive (cmdentry : libentries)
        newjarbytes = fromArchive $ addEntryToArchive appzip (toArchive jarbytes)
    BS.writeFile ("." </> takeBaseName cmd <.> "jar") newjarbytes
  where
    mkEntry file = toEntry (takeFileName file) 0 <$> BS.readFile file

main :: IO ()
main = do
    argv <- getArgs
    case argv of
      ["--base-jar", baseJar, path] -> doPackage baseJar path
      [path] -> do
        dir <- getDataDir
        -- Use executables' base jar by default.
        doPackage (dir </> "build/libs/stub.jar") path
      _ -> fail "Usage: jarify [--base-jar FILE] <command>"
