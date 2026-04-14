module Main where

import Config qualified
import Server qualified
import Kubernetes qualified
import Types (KubernetesEnv(..))

main :: IO ()
main = do
    config <- Config.get
    putStrLn "--- Starting Kubernetes MCP ---"
    putStrLn $ "Environment: " ++ show (Config.env config)
    let env = KubernetesEnv Kubernetes.getNamespaces Kubernetes.getResources Kubernetes.getLogs
    Server.run config env
