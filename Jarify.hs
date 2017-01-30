{-# LANGUAGE LambdaCase #-}

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
import Data.List (isInfixOf)
import qualified Data.ByteString.Lazy as BS
import Paths_jarify
import System.Directory (doesFileExist)
import System.Environment (getArgs)
import System.FilePath ((</>), (<.>), isAbsolute, takeBaseName, takeFileName)
import System.Info (os)
import System.IO (hPutStrLn, stderr)
import System.Process (readProcess)
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
    libentries <- mapM mkEntry libs
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
