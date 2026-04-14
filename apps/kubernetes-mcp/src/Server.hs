{-# LANGUAGE OverloadedStrings #-}

module Server (run) where

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
-- WAI application
-------------------------------------------------------------------------------
router :: Config -> Application
router cfg request response =
    case pathInfo request of
        -- GET /status
        ["status"] ->
            response $ responseLBS status200 [("Content-Type", "application/json")] "{\"ok\": true}"
        -- response $ responseLBS status200 [("Content-Type", "application/json")] "{\"ok\": true, \"second_key\": \"hellothere\"}"

        -- Get /health
        ["health"] ->
            response $ responseLBS status200 [] "OK"
        -- GET /env
        ["env"] ->
            let msg = "Current Environment: " ++ show (Config.env cfg)
             in response $ responseLBS status200 [("Content-Type", "text/plain")] (fromString msg)
        -- 404 Fallback
        _ ->
            response $ responseLBS status404 [("Content-Type", "text/plain")] "Not Found"

-------------------------------------------------------------------------------
-- Run the webserver
-------------------------------------------------------------------------------
run :: Config -> IO ()
run cfg = do
    let (Config.Port port) = Config.port cfg

    let settings =
            setPort port $
                setHost (fromString "0.0.0.0") $
                    setBeforeMainLoop (putStrLn $ "Socket bound. Ready for requests on port " ++ show port) defaultSettings

    -- Warp takes the 'router' function as its entrypoint
    runSettings settings (router cfg)
