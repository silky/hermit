module Main where

import HList
-- import Seq

import Data.Function (fix)

rev :: [a] -> [a]
rev []     = []
rev (x:xs) = rev xs ++ [x]

main :: IO ()
main = print $ rev "hello"
