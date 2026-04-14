{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types where

import Data.Aeson (FromJSON (..), ToJSON (..), Value, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | JSON-RPC Request structure sent from Client to Server
data JsonRpcRequest = JsonRpcRequest
    { reqJsonrpc :: Text
    , reqId :: Maybe Value
    , reqMethod :: Text
    , reqParams :: Maybe Value
    }
    deriving (Show, Eq, Generic)

instance FromJSON JsonRpcRequest where
    parseJSON = Aeson.withObject "JsonRpcRequest" $ \o ->
        JsonRpcRequest
            <$> o .: "jsonrpc"
            <*> o .:? "id"
            <*> o .: "method"
            <*> o .:? "params"

-- | JSON-RPC Response structure sent from Server to Client
data JsonRpcResponse = JsonRpcResponse
    { resJsonrpc :: Text
    , resId :: Value
    , resResult :: Maybe Value
    , resError :: Maybe Value
    }
    deriving (Show, Eq, Generic)

instance ToJSON JsonRpcResponse where
    toJSON r =
        Aeson.object $
            [ "jsonrpc" .= resJsonrpc r
            , "id" .= resId r
            ]
                ++ ( case resResult r of
                        Just res -> ["result" .= res]
                        Nothing -> []
                   )
                ++ ( case resError r of
                        Just err -> ["error" .= err]
                        Nothing -> []
                   )

-- | Strongly typed Supported Kubernetes Resources
data ResourceType = Pods | Services | Deployments
    deriving (Show, Eq, Generic)

instance FromJSON ResourceType where
    parseJSON = Aeson.withText "ResourceType" $ \t -> case T.toLower t of
        "pods"        -> pure Pods
        "pod"         -> pure Pods
        "services"    -> pure Services
        "service"     -> pure Services
        "deployments" -> pure Deployments
        "deployment"  -> pure Deployments
        _             -> fail $ "Unsupported resource type: " ++ T.unpack t

-- | Dependency Injection Environment for Kubernetes Side-Effects
data KubernetesEnv = KubernetesEnv
    { envGetNamespaces :: IO (Either Text Text)
    , envGetResources  :: ResourceType -> Text -> IO (Either Text Text)
    , envGetLogs       :: ResourceType -> Text -> Text -> IO (Either Text Text)
    }
