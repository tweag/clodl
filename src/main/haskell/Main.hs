{-# LANGUAGE FlexibleContexts #-}
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
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString as SBS
import System.Directory (copyFile, doesFileExist)
import System.Environment (getArgs, getExecutablePath)
import System.FilePath ((</>), (<.>), isAbsolute, takeBaseName, takeFileName)
import System.Exit (ExitCode(..))
import System.Info (os)
import System.IO (hPutStrLn, stderr)
import System.IO.Temp (withSystemTempFile, withSystemTempDirectory)
import System.Posix.Files (createSymbolicLink)
import System.Process
  ( CreateProcess(..)
  , callProcess
  , proc
  , readProcess
  , waitForProcess
  , withCreateProcess
  )
import Text.Regex.TDFA

stripString :: String -> String
stripString = unpack . strip . pack

-- | Add @$ORIGIN@ to RPATH and dependency on @libHSjarify.so@.
patchElf :: FilePath -> IO ()
patchElf exe = do
    rpath <- readProcess "patchelf" ["--print-rpath", exe] ""
    let newrpath = intercalate ":" ["$ORIGIN", stripString rpath]
    callProcess "patchelf" ["--set-rpath", newrpath, exe]

doPackage :: FilePath -> FilePath -> IO ()
doPackage baseJar cmd = do
    jarbytes <- LBS.readFile baseJar
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
      self <- getExecutablePath
      selfldd <- readProcess "ldd" [self] ""
      let unresolved =
            map fst $
            filter (not . isAbsolute . snd) $
            map (\xs -> (xs !! 1, xs !! 2)) (ldd =~ "(.+) => (.+)" :: [[String]])
          matchOutput xs =
            map (!! 1) (xs =~ " => (.*) \\(0x[0-9a-f]+\\)" :: [[String]])
          libs =
            filter
              (\x -> not $ any (`isInfixOf` x) ["libc.so", "libpthread.so"])
              (matchOutput ldd) ++
            -- Guarantee that libHSjarify is part of libs set.
            filter
              ("libHSjarify" `isInfixOf`)
              (matchOutput selfldd)
      unless (null unresolved) $
        fail $
          "Unresolved libraries in " ++
          cmdpath ++
          ":\n" ++
          unlines unresolved
      (, libs) <$> LBS.readFile tmp
    libentries0 <- mapM mkEntry libs
    libentries <-
      if os == "darwin" then return libentries0
      else do
        libhsapp <- makeHsTopLibrary cmdpath libs
        return $ toEntry "libhsapp.so" 0 libhsapp : libentries0
    let cmdentry = toEntry "hsapp" 0 hsapp
        appzip =
          toEntry "jarify-app.zip" 0 $
          fromArchive $
          foldr addEntryToArchive emptyArchive (cmdentry : libentries)
        newjarbytes = fromArchive $ addEntryToArchive appzip (toArchive jarbytes)
    LBS.writeFile ("." </> takeBaseName cmd <.> "jar") newjarbytes
  where
    mkEntry file = toEntry (takeFileName file) 0 <$> LBS.readFile file

-- We make a library which depends on all the libraries that go into the jar.
-- This removes the need to fiddle with the rpaths of the various libraries
-- and the application executable.
makeHsTopLibrary :: FilePath -> [FilePath] -> IO LBS.ByteString
makeHsTopLibrary hsapp libs = withSystemTempDirectory "libhsapp" $ \d -> do
    let f = d </> "libhsapp.so"
    createSymbolicLink hsapp (d </> "hsapp")
    -- Changing the directory is necessary for gcc to link hsapp with a
    -- relative path. "-L d -l:hsapp" doesn't work in centos 6 where the
    -- path to hsapp in the output library ends up being absolute.
    callProcessCwd d "gcc" $
      [ "-shared", "-Wl,-z,origin", "-Wl,-rpath=$ORIGIN", "hsapp"
      , "-o", f] ++ libs
    LBS.fromStrict <$> SBS.readFile f

-- This is a variant of 'callProcess' which takes a working directory.
callProcessCwd :: FilePath -> FilePath -> [String] -> IO ()
callProcessCwd wd cmd args = do
    exit_code <-
      withCreateProcess
        (proc cmd args)
          { delegate_ctlc = True
          , cwd = Just wd
          } $ \_ _ _ p -> waitForProcess p
    case exit_code of
      ExitSuccess -> return ()
      ExitFailure r -> error $ "callProcessCwd: " ++ show (cmd, args, r)

main :: IO ()
main = do
    argv <- getArgs
    case argv of
      ["--base-jar", baseJar, path] -> doPackage baseJar path
      _ -> fail "Usage: jarify --base-jar <file> <command>"
