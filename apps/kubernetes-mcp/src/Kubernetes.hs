{-# LANGUAGE OverloadedStrings #-}

module Kubernetes 
    ( getNamespaces
    , getResources
    , getLogs
    ) where

import Control.Exception (try, SomeException)
import Control.Concurrent.STM (atomically, newTVar)
import qualified Data.Map as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as BSL
import Data.Aeson (encode, ToJSON)
import Kubernetes.Client (KubeConfigSource(..), mkKubeClientConfig)
import Kubernetes.OpenAPI (Accept(..), MimeJSON(..), dispatchMime, MimeResult(..), KubernetesRequest)
import qualified Kubernetes.OpenAPI.API.CoreV1 as CoreV1
import qualified Kubernetes.OpenAPI.API.AppsV1 as AppsV1
import System.Environment (getEnv)
import Types (ResourceType(..))

-- | Boilerplate abstractor for executing an arbitrary typed SDK request
runApiRequest :: (ToJSON res) => KubernetesRequest req contentType res accepts -> IO (Either Text Text)
runApiRequest req = do
    home <- getEnv "HOME"
    oidcCache <- atomically $ newTVar Map.empty
    (mgr, kcfg) <- mkKubeClientConfig oidcCache (KubeConfigFile (home ++ "/.kube/config"))
    
    res <- try (dispatchMime mgr kcfg req)
    case res of
        Right (MimeResult _ _ body) -> 
            return . Right . TE.decodeUtf8 . BSL.toStrict $ encode body
        Left err -> 
            return . Left . T.pack $ show (err :: SomeException)

-- | Pure function bridging the ADT routing logic
resourceRequest :: ResourceType -> Text -> IO (Either Text Text)
resourceRequest Pods ns = runApiRequest $ CoreV1.listNamespacedPod (Accept MimeJSON) ns
resourceRequest Services ns = runApiRequest $ CoreV1.listNamespacedService (Accept MimeJSON) ns
resourceRequest Deployments ns = runApiRequest $ AppsV1.listNamespacedDeployment (Accept MimeJSON) ns

-- | Public Facing API endpoints
getNamespaces :: IO (Either Text Text)
getNamespaces = runApiRequest $ CoreV1.listNamespace (Accept MimeJSON)

getResources :: ResourceType -> Text -> IO (Either Text Text)
getResources = resourceRequest

getLogs :: ResourceType -> Text -> Text -> IO (Either Text Text)
getLogs Pods name ns = runApiRequest $ CoreV1.readNamespacedPodLog name ns
getLogs _ _ _ = return $ Left "Fetching logs is currently only supported for Pods."
