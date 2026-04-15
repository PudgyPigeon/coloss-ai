module Main where

import Config qualified
import Server qualified

main :: IO ()
main = do
    config <- Config.get
    Server.run config
