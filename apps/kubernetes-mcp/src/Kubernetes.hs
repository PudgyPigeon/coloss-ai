{-# LANGUAGE OverloadedStrings #-}

module Kubernetes (handleTool) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import MCP.Server (Content (..))
import System.Exit (ExitCode (..))
import System.Process.Typed (proc, readProcess)
import Types

import Data.ByteString.Lazy qualified as LBS
import Data.Aeson qualified as A
import Data.Aeson ((.=))

-------------------------------------------------------------------------------
-- Tool Handler
-------------------------------------------------------------------------------

-- | Dispatch an MCP tool call to the corresponding kubectl command.
handleTool :: K8sTool -> IO Content

-- ==========================================
-- TIER 1: DISCOVERY (Clean custom-columns)
-- ==========================================
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
    -- Nodes are cluster-scoped, so no namespace flag is needed
    kubectl ["get", "nodes", "--no-headers", "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type==\"Ready\")].status,AGE:.metadata.creationTimestamp"]


-- ==========================================
-- TIER 2: INSPECTION (Full JSON data)
-- ==========================================
handleTool (GetPod ns n) = kubectl ["get", "pod", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetDeployment ns n) = kubectl ["get", "deployment", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetService ns n) = kubectl ["get", "service", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (GetPVC ns n) = kubectl ["get", "pvc", T.unpack n, "-n", T.unpack ns, "-o", "json"]


-- ==========================================
-- TIER 3: DEEP DEBUGGING
-- ==========================================
handleTool (DescribeResource k ns n) =
    -- Example: kubectl describe deployment my-app -n default
    kubectl ["describe", T.unpack k, T.unpack n, "-n", T.unpack ns]

handleTool (GetLogs k ns n tl) =
    -- Supports logs for pods, deployments, statefulsets, etc.
    let limit  = if tl <= 0 then "20" else show tl
        target = T.unpack k <> "/" <> T.unpack n
    in kubectl ["logs", target, "-n", T.unpack ns, "--tail", limit]

handleTool (GetEvents ns) =
    kubectl ["get", "events", "-n", T.unpack ns, "-o", "json"]


-------------------------------------------------------------------------------
-- kubectl subprocess (SMART JSON WRAPPER)
-------------------------------------------------------------------------------

-- | Run a kubectl command and return the output as MCP Content.
-- Automatically wraps plain text in JSON to prevent Open WebUI parsing crashes.
kubectl :: [String] -> IO Content
kubectl args = do
    (exitCode, stdout, stderr) <- readProcess (proc "kubectl" args)
    
    let outText = TE.decodeUtf8 $ LBS.toStrict stdout
        errText = TE.decodeUtf8 $ LBS.toStrict stderr
        
        -- Check if the output is already valid JSON (starts with { or [)
        isJson = "{" `T.isPrefixOf` T.stripStart outText || "[" `T.isPrefixOf` T.stripStart outText

    case exitCode of
        ExitSuccess ->
            if isJson
                then pure $ ContentText outText
                else 
                    -- Wrap plain text tables in a valid JSON object
                    let jsonObj = A.object ["output" .= outText]
                    in pure $ ContentText $ TE.decodeUtf8 $ LBS.toStrict $ A.encode jsonObj
                    
        ExitFailure code ->
            -- Wrap errors in a JSON object so the UI doesn't crash on failure
            let errMsg = "kubectl failed (exit " <> T.pack (show code) <> "): " <> errText
                errObj = A.object ["error" .= errMsg]
            in pure $ ContentText $ TE.decodeUtf8 $ LBS.toStrict $ A.encode errObj