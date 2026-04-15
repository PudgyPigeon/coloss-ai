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

-------------------------------------------------------------------------------
-- Tool Handler
-------------------------------------------------------------------------------

-- | Dispatch an MCP tool call to the corresponding kubectl command.
handleTool :: K8sTool -> IO Content
handleTool (ListPods ns) =
    kubectl ["get", "pods", "-n", T.unpack ns, "-o", "json"]
handleTool (GetPod ns n) =
    kubectl ["get", "pod", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (ListServices ns) =
    kubectl ["get", "services", "-n", T.unpack ns, "-o", "json"]
handleTool (GetService ns n) =
    kubectl ["get", "service", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool (ListDeployments ns) =
    kubectl ["get", "deployments", "-n", T.unpack ns, "-o", "json"]
handleTool (GetDeployment ns n) =
    kubectl ["get", "deployment", T.unpack n, "-n", T.unpack ns, "-o", "json"]
handleTool ListNamespaces =
    kubectl ["get", "namespaces", "-o", "json"]
handleTool (GetPodLogs ns n tl) =
    kubectl ["logs", T.unpack n, "-n", T.unpack ns, "--tail", show tl]
handleTool (DescribePod ns n) =
    kubectl ["describe", "pod", T.unpack n, "-n", T.unpack ns]
handleTool (GetEvents ns) =
    kubectl ["get", "events", "-n", T.unpack ns, "-o", "json"]

-------------------------------------------------------------------------------
-- kubectl subprocess
-------------------------------------------------------------------------------

-- | Run a kubectl command and return the output as MCP Content.
-- On failure, returns the stderr output as an error message.
kubectl :: [String] -> IO Content
kubectl args = do
    (exitCode, stdout, stderr) <- readProcess (proc "kubectl" args)
    case exitCode of
        ExitSuccess ->
            pure $ ContentText $ TE.decodeUtf8 $ LBS.toStrict stdout
        ExitFailure code ->
            pure $
                ContentText $
                    "kubectl failed (exit "
                        <> T.pack (show code)
                        <> "): "
                        <> TE.decodeUtf8 (LBS.toStrict stderr)
