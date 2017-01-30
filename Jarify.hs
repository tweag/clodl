{-# LANGUAGE LambdaCase #-}

module Main where

import Control.Applicative (liftA2)
import Codec.Archive.Zip
  ( addEntryToArchive
  , emptyArchive
  , fromArchive
  , toArchive
  , toEntry
  )
import Data.Text (pack, strip, unpack)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import qualified Data.ByteString.Lazy as BS
import Paths_jarify
import System.Directory (doesFileExist, getDirectoryContents)
import System.Environment (getArgs)
import System.Exit
import System.FilePath ((</>), (<.>), takeBaseName, takeFileName)
import System.Info (os)
import System.IO (hPutStrLn, stderr)
import System.Process (readProcess, system)
import Text.Regex.TDFA

doPackage :: FilePath -> IO ()
doPackage cmd = do
    dir <- getDataDir
    jarbytes <- BS.readFile (dir </> "build/libs/stub.jar")
    cmdpath <- doesFileExist cmd >>= \case
      False -> unpack . strip . pack <$> readProcess "which" [cmd] ""
      True -> return cmd
    ldd <- case os of
      "darwin" -> do
        hPutStrLn
          stderr
          "WARNING: JAR not self contained on OS X (shared libraries not copied)."
        return ""
      _ -> readProcess "ldd" [cmdpath] ""
    let libs =
          filter (\x -> not $ any (`isInfixOf` x) ["libc.so", "libpthread.so"]) $
          map (!! 1) (ldd =~ " => ([[:graph:]]+) " :: [[String]])
    libentries <- mapM mkEntry libs
 
    ------------------------------------------------------------
    -- fix the linking issue
    readProcess "patchelf" ["--set-rpath", "$ORIGIN", cmdpath] ""

    -- add the .so dependency
    lib <- getLibDir
    files <- getDirectoryContents $ lib </> ".."
    let so = head $
          filter (liftA2 (&&) (isSuffixOf ".so") (isPrefixOf "libHSjarify")) files
    readProcess "patchelf" ["--add-needed", lib </> ".." </> so, cmdpath] ""
    -------------------------------------------------------------

    cmdentry <- toEntry "hsapp" 0 <$> BS.readFile cmdpath
    let appzip =
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
      [cmd] -> doPackage cmd
      _ -> fail "Usage: jarify <command>"
