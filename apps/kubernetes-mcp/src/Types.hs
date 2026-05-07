{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Types where

import           Data.Aeson
import           Data.Text    (Text)
import           GHC.Generics (Generic)
import           Data.Maybe   (fromMaybe)

-------------------------------------------------------------------------------
-- MCP Tool ADT
-------------------------------------------------------------------------------

data K8sTool
    = -- Tier 1: Discovery
      ListPods        { namespace :: Text }
    | ListDeployments { namespace :: Text }
    | ListServices    { namespace :: Text }
    | ListPVCs        { namespace :: Text }
    | ListNamespaces
    | ListNodes
    | -- Tier 2: Inspection
      GetPod        { namespace :: Text, name :: Text }
    | GetDeployment { namespace :: Text, name :: Text }
    | GetService    { namespace :: Text, name :: Text }
    | GetPVC        { namespace :: Text, name :: Text }
    | -- Tier 3: Deep Debugging
      -- Made 'kind' and 'tailLines' optional to handle LLM forgetfulness
      GetLogs 
        { kind      :: Maybe Text 
        , namespace :: Text 
        , name      :: Text 
        , tailLines :: Maybe Int 
        }
    | DescribeResource 
        { kind      :: Maybe Text 
        , namespace :: Text 
        , name      :: Text 
        }
    | GetEvents { namespace :: Text }
    deriving (Show, Eq, Generic)

-- Custom JSON options to handle the 'pod_name' drift and the MCP structure
instance FromJSON K8sTool where
    parseJSON = genericParseJSON defaultOptions
        { fieldLabelModifier = \f -> if f == "name" then "pod_name" else f
        , constructorTagModifier = \c -> case c of
            "ListPods" -> "list_pods"
            "ListDeployments" -> "list_deployments"
            "ListServices" -> "list_services"
            "ListPVCs" -> "list_pvcs"
            "ListNamespaces" -> "list_namespaces"
            "ListNodes" -> "list_nodes"
            "GetPod" -> "get_pod"
            "GetDeployment" -> "get_deployment"
            "GetService" -> "get_service"
            "GetPVC" -> "get_pvc"
            "GetLogs" -> "get_logs"
            "DescribeResource" -> "describe_resource"
            "GetEvents" -> "get_events"
            _ -> c
        , sumEncoding = TaggedObject "name" "arguments"
        }