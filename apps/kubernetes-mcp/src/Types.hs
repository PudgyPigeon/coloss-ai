{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Types where

import Data.Text (Text)

-------------------------------------------------------------------------------
-- MCP Tool ADT
-------------------------------------------------------------------------------

data K8sTool
    -- Tier 1: Discovery (Lists)
    = ListPods {namespace :: Text}
    | ListDeployments {namespace :: Text}
    | ListServices {namespace :: Text}
    | ListPVCs {namespace :: Text}
    | ListNamespaces
    | ListNodes

    -- Tier 2: Inspection (Gets)
    | GetPod {namespace :: Text, name :: Text}
    | GetDeployment {namespace :: Text, name :: Text}
    | GetService {namespace :: Text, name :: Text}
    | GetPVC {namespace :: Text, name :: Text}

    -- Tier 3: Deep Debugging
    -- 'kind' can be "pod", "deployment", "service", "node", "pvc", etc.
    | GetLogs {kind :: Text, namespace :: Text, name :: Text, tailLines :: Int}
    | DescribeResource {kind :: Text, namespace :: Text, name :: Text}
    | GetEvents {namespace :: Text}
    deriving (Show, Eq)