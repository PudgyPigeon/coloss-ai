{-# LANGUAGE OverloadedStrings #-}

module Health (runHealthServer) where

import Config (Config)
import Config qualified
import Data.String (fromString)
import Network.HTTP.Types (status200, status404)
import Network.Wai (Application, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (
    defaultSettings,
    runSettings,
    setBeforeMainLoop,
    setHost,
    setPort,
 )

-------------------------------------------------------------------------------
-- Health / Readiness probe server
-- Runs on a separate port from the MCP server for K8s probes.
-------------------------------------------------------------------------------

healthApp :: Config -> Application
healthApp cfg request response =
    case pathInfo request of
        -- GET /health — liveness probe
        ["health"] ->
            response $ responseLBS status200 [] "OK"
        -- GET /status — readiness probe
        ["status"] ->
            response $
                responseLBS
                    status200
                    [("Content-Type", "application/json")]
                    "{\"ok\": true}"
        -- GET /env
        ["env"] ->
            let msg = "Current Environment: " ++ show (Config.env cfg)
             in response $ responseLBS status200 [("Content-Type", "text/plain")] (fromString msg)
        -- 404 Fallback
        _ ->
            response $ responseLBS status404 [("Content-Type", "text/plain")] "Not Found"

-- | Start the health check server on the configured health port.
-- This should be run in a separate thread alongside the MCP server.
runHealthServer :: Config -> IO ()
runHealthServer cfg = do
    let (Config.Port hp) = Config.healthPort cfg
    let settings =
            setPort hp $
                setHost (fromString "0.0.0.0") $
                    setBeforeMainLoop
                        (putStrLn $ "Health server ready on port " ++ show hp)
                        defaultSettings
    runSettings settings (healthApp cfg)
