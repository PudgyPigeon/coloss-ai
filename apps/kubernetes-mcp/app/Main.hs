module Main where

import Config qualified
import Server qualified

main :: IO ()
main = do
    config <- Config.get
    putStrLn "--- Starting Kubernetes MCP ---"
    putStrLn $ "Environment: " ++ show (Config.env config)
    Server.run config
