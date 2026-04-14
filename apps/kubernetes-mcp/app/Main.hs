module Main where

import qualified Config
import qualified Server 

main :: IO()
main = do
  config <- Config.get
  putStrLn $ "--- Starting Kubernetes MCP ---"
  putStrLn $ "Environment: " ++ show (Config.env config)
  Server.run config



-- main = do
--   config <- Config.get
--   print $ "Starting server in environment: " ++ show (config)
--   Server.run config

