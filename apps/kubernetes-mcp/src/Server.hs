{-# LANGUAGE OverloadedStrings #-}
module Server (run) where

import Config (Config)
import qualified Config 
import Network.Wai (Application, responseLBS, pathInfo)
import Network.HTTP.Types (status200, status404)
import Network.Wai.Handler.Warp 
    ( runSettings
    , setPort
    , setHost
    , setBeforeMainLoop
    , defaultSettings
    )
import Data.String (fromString)
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
run :: Config -> IO()
run cfg = do 
    let (Config.Port port) = Config.port cfg
    
    let settings = setPort port 
                 $ setHost (fromString "0.0.0.0")
                 $ setBeforeMainLoop (putStrLn $ "Socket bound. Ready for requests on port " ++ show port)                 
                 $ defaultSettings
    
    -- Warp takes the 'router' function as its entrypoint
    runSettings settings (router cfg)