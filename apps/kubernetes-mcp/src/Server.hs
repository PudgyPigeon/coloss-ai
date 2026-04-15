{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Server (run) where

import Config (Config)
import Config qualified
import Control.Concurrent (forkIO)
import Health qualified
import Kubernetes (handleTool)
import MCP.Server (
    McpServerHandlers (..),
    McpServerInfo (..),
    runMcpServerStdio,
 )
import MCP.Server.Derive (deriveToolHandler)
import MCP.Server.Transport.Http (HttpConfig (..), defaultHttpConfig, transportRunHttp)
import Types (K8sTool)

-------------------------------------------------------------------------------
-- MCP Server Info
-------------------------------------------------------------------------------
serverInfo :: McpServerInfo
serverInfo =
    McpServerInfo
        { serverName = "kubernetes-mcp"
        , serverVersion = "0.1.0.0"
        , serverInstructions =
            "Kubernetes cluster operations via MCP. "
                <> "Provides tools to list/get pods, services, deployments, "
                <> "namespaces, pod logs, and events."
        }

-------------------------------------------------------------------------------
-- MCP Handlers (derived via Template Haskell)
-------------------------------------------------------------------------------
-- Maybe pattern: Nothing means "we don't support this". Just x means "here's the implementation". This is how the library knows which MCP features to advertise.
-- Template Haskell ($(...)) runs at compile time. The $() is what triggers it. Inside:
-- ''K8sTool — double tick '' means "give me the type named K8sTool" (your ADT in Types.hs)
-- 'handleTool — single tick ' means "give me the function named handleTool" (your kubectl dispatcher in Kubernetes.hs)
handlers :: McpServerHandlers IO
handlers =
    McpServerHandlers
        { prompts = Nothing
        , resources = Nothing
        , tools = Just $(deriveToolHandler ''K8sTool 'handleTool)
        }

-------------------------------------------------------------------------------
-- Run the MCP server
-------------------------------------------------------------------------------
run :: Config -> IO ()
run cfg = do
    _ <- forkIO $ Health.runHealthServer cfg

    case Config.transport cfg of
        Config.Stdio -> runMcpServerStdio serverInfo handlers
        Config.Http ->
            transportRunHttp httpCfg serverInfo handlers
          where
            (Config.Port p) = Config.port cfg
            httpCfg =
                defaultHttpConfig
                    { httpPort = p
                    , httpHost = "0.0.0.0"
                    , httpEndpoint = "/mcp"
                    , httpVerbose = Config.env cfg == Config.Dev
                    }

