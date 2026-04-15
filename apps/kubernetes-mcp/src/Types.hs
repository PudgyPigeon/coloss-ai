{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Types where

import Data.Text (Text)

-------------------------------------------------------------------------------
-- MCP Tool ADT
-- Each constructor becomes a discoverable MCP tool via TH derivation.
-- Constructor names are auto-converted to snake_case by mcp-server.
-------------------------------------------------------------------------------

-- | Kubernetes operations exposed as MCP tools.
-- Field names become the JSON Schema properties in the tool's inputSchema.
data K8sTool
    = ListPods {namespace :: Text}
    | GetPod {namespace :: Text, name :: Text}
    | ListServices {namespace :: Text}
    | GetService {namespace :: Text, name :: Text}
    | ListDeployments {namespace :: Text}
    | GetDeployment {namespace :: Text, name :: Text}
    | ListNamespaces
    | GetPodLogs {namespace :: Text, name :: Text, tailLines :: Int}
    | DescribePod {namespace :: Text, name :: Text}
    | GetEvents {namespace :: Text}
    deriving (Show, Eq)
