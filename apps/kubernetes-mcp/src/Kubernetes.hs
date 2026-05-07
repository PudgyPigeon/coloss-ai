{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Kubernetes (handleTool) where

import           Data.Aeson            ((.=))
import           Data.Aeson            qualified as A
import           Data.ByteString.Lazy  qualified as LBS
import           Data.Maybe            (fromMaybe)
import           Data.Text             (Text)
import           Data.Text             qualified as T
import           Data.Text.Encoding    qualified as TE
import           MCP.Server            (Content (..))
import           System.Exit           (ExitCode (..))
import           System.Process.Typed  (proc, readProcess)
import           Types

-------------------------------------------------------------------------------
-- Tool Handler
-------------------------------------------------------------------------------

handleTool :: K8sTool -> IO Content

-- DISCOVERY
handleTool (ListPods ns) =
    kubectl ["get", "pods", "-n", T.unpack ns, "--no-headers", "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp"]
handleTool (ListDeployments ns) =
    kubectl ["get", "deployments", "-n", T.unpack ns, "--no-headers", "-o", "custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas"]
handleTool (ListServices ns) =
    kubectl ["get", "services", "-n", T.unpack ns, "--no-headers", "-o", "custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP"]
handleTool (ListPVCs ns) =
    kubectl ["get", "pvc", "-n", T.unpack ns, "--no-headers", "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,SIZE:.status.capacity.storage"]
handleTool ListNamespaces =
    kubectl ["get", "namespaces", "--no-headers", "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.phase"]
handleTool ListNodes =
    kubectl ["get", "nodes", "--no-headers", "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type==\"Ready\")].status,AGE:.metadata.creationTimestamp"]

-- INSPECTION
handleTool (GetPod ns n) = kubectl ["get", "pod", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetDeployment ns n) = kubectl ["get", "deployment", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetService ns n) = kubectl ["get", "service", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetPVC ns n) = kubectl ["get", "pvc", T.unpack n, "-n", T.unpack ns, "-o", "json"]

-- DEEP DEBUGGING
handleTool (DescribeResource k ns n) =
    let resourceKind = T.unpack (fromMaybe "pod" k)
     in kubectl ["describe", resourceKind, T.unpack n, "-n", T.unpack ns]

handleTool (GetLogs k ns n tl) =
    let resourceKind = T.unpack (fromMaybe "pod" k)
        limit = show (fromMaybe 50 tl)
        target = resourceKind <> "/" <> T.unpack n
     in kubectl ["logs", target, "-n", T.unpack ns, "--tail", limit]

handleTool (GetEvents ns) =
    kubectl ["get", "events", "-n", T.unpack ns, "-o", "json"]

-------------------------------------------------------------------------------
-- kubectl subprocess
-------------------------------------------------------------------------------

kubectl :: [String] -> IO Content
kubectl args = do
    (exitCode, stdout, stderr) <- readProcess (proc "kubectl" args)
    let outText = TE.decodeUtf8 $ LBS.toStrict stdout
        errText = TE.decodeUtf8 $ LBS.toStrict stderr
        isJson = "{" `T.isPrefixOf` T.stripStart outText || "[" `T.isPrefixOf` T.stripStart outText

    case exitCode of
        ExitSuccess ->
            if isJson
                then pure $ ContentText outText
                else let jsonObj = A.object ["output" .= outText]
                      in pure $ ContentText $ TE.decodeUtf8 $ LBS.toStrict $ A.encode jsonObj
        ExitFailure code ->
            let errMsg = "kubectl failed (exit " <> T.pack (show code) <> "): " <> errText
                errObj = A.object ["error" .= errMsg]
             in pure $ ContentText $ TE.decodeUtf8 $ LBS.toStrict $ A.encode errObj