{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

foreign export ccall mainEntryPoint :: IO ()

mainEntryPoint :: IO ()
mainEntryPoint = main

main :: IO ()
main = print "hello"
