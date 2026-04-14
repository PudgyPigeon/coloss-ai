{-# LANGUAGE OverloadedStrings #-}

module Server (run, routeRpc) where

import Config (Config)
import qualified Config
import Control.Concurrent.Chan (Chan, dupChan, newChan, readChan, writeChan)
import Data.Aeson (Value(..), decode, encode, object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import Data.ByteString.Builder (lazyByteString, stringUtf8)
import Data.Maybe (fromMaybe)
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Kubernetes
import Network.HTTP.Types (status200, status202, status404)
import Network.Wai (Application, lazyRequestBody, pathInfo, requestMethod, responseLBS)
import Network.Wai.EventSource (ServerEvent(..), eventSourceAppIO)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setBeforeMainLoop, setHost, setPort)
import Types

-------------------------------------------------------------------------------
-- Pure Routing Pipeline
-------------------------------------------------------------------------------
-- | Transforms a valid JSON-RPC request purely into an IO computation of its Response
routeRpc :: KubernetesEnv -> JsonRpcRequest -> IO JsonRpcResponse
routeRpc env req = case reqMethod req of
    "initialize"  -> pure $ handleInitialize req
    "tools/list"  -> pure $ handleListTools req
    "tools/call"  -> handleCallTool env req
    _             -> pure $ handleError req

handleInitialize :: JsonRpcRequest -> JsonRpcResponse
handleInitialize req = JsonRpcResponse "2.0" (fromMaybe Null (reqId req)) result Nothing
  where
    result = Just $ object
        [ "protocolVersion" .= ("2024-11-05" :: Text)
        , "capabilities" .= object ["tools" .= object []]
        , "serverInfo" .= object ["name" .= ("kubernetes-mcp" :: Text), "version" .= ("0.1.0" :: Text)]
        ]

handleListTools :: JsonRpcRequest -> JsonRpcResponse
handleListTools req = JsonRpcResponse "2.0" (fromMaybe Null (reqId req)) result Nothing
  where
    result = Just $ object
        [ "tools" .= 
            [ object
                [ "name" .= ("get_namespaces" :: Text)
                , "description" .= ("Get a list of all Kubernetes namespaces" :: Text)
                , "inputSchema" .= object ["type" .= ("object"::Text), "properties" .= object [], "required" .= ([]::[Text])]
                ]
            , object
                [ "name" .= ("get_resources" :: Text)
                , "description" .= ("Get all resources of a specific type in a namespace" :: Text)
                , "inputSchema" .= object
                    [ "type" .= ("object"::Text)
                    , "properties" .= object
                        [ "resource_type" .= object ["type" .= ("string"::Text), "description" .= ("pods, services, or deployments"::Text)]
                        , "namespace" .= object ["type" .= ("string"::Text), "description" .= ("The namespace to query in"::Text)]
                        ]
                    , "required" .= (["resource_type", "namespace"] :: [Text])
                    ]
                ]
            , object
                [ "name" .= ("get_logs" :: Text)
                , "description" .= ("Get logs for a specific resource" :: Text)
                , "inputSchema" .= object
                    [ "type" .= ("object"::Text)
                    , "properties" .= object
                        [ "resource_type" .= object ["type" .= ("string"::Text), "description" .= ("pods"::Text)]
                        , "resource_name" .= object ["type" .= ("string"::Text), "description" .= ("The name of the Kubernetes resource" :: Text)]
                        , "namespace" .= object ["type" .= ("string"::Text), "description" .= ("The namespace to query in"::Text)]
                        ]
                    , "required" .= (["resource_type", "resource_name", "namespace"] :: [Text])
                    ]
                ]
            ]
        ]

handleCallTool :: KubernetesEnv -> JsonRpcRequest -> IO JsonRpcResponse
handleCallTool env req = do
    let (toolName, toolArgs) = extractToolParams (reqParams req)
    resEither <- case toolName of
        "get_namespaces" -> envGetNamespaces env
        "get_resources"  -> do
            let rt = extractText "resource_type" toolArgs
            let ns = extractText "namespace" toolArgs
            -- Map dynamic text to strictly typed ResourceType
            case Aeson.fromJSON (String rt) of
                Aeson.Success parsedRt -> envGetResources env parsedRt ns
                Aeson.Error err -> pure $ Left (T.pack err)
        "get_logs" -> do
            let rt = extractText "resource_type" toolArgs
            let rn = extractText "resource_name" toolArgs
            let ns = extractText "namespace" toolArgs
            case Aeson.fromJSON (String rt) of
                Aeson.Success parsedRt -> envGetLogs env parsedRt rn ns
                Aeson.Error err -> pure $ Left (T.pack err)
        _ -> pure $ Left "Tool not found"
    
    pure $ case resEither of
        Right successText ->
            JsonRpcResponse "2.0" (fromMaybe Null (reqId req)) (Just $ contentBlock successText False) Nothing
        Left errorText ->
            JsonRpcResponse "2.0" (fromMaybe Null (reqId req)) (Just $ contentBlock errorText True) Nothing
  where
    contentBlock txt isErr = object
        [ "content" .= [object ["type" .= ("text"::Text), "text" .= txt]]
        , "isError" .= isErr
        ]

handleError :: JsonRpcRequest -> JsonRpcResponse
handleError req = JsonRpcResponse "2.0" (fromMaybe Null (reqId req)) Nothing (Just errObj)
  where
    errObj = object ["code" .= (-32601 :: Int), "message" .= ("Method not found" :: Text)]

-------------------------------------------------------------------------------
-- Pure parameter extractors
-------------------------------------------------------------------------------
extractToolParams :: Maybe Value -> (Text, Maybe Value)
extractToolParams (Just (Object obj)) =
    case (KeyMap.lookup "name" obj, KeyMap.lookup "arguments" obj) of
        (Just (String n), args) -> (n, args)
        _ -> ("", Nothing)
extractToolParams _ = ("", Nothing)

extractText :: Text -> Maybe Value -> Text
extractText key (Just (Object obj)) =
    case KeyMap.lookup (AesonKey.fromText key) obj of
        Just (String s) -> s
        _ -> ""
extractText _ _ = ""

-------------------------------------------------------------------------------
-- Side Effect Boundaries
-------------------------------------------------------------------------------
dispatchMessage :: KubernetesEnv -> JsonRpcRequest -> Chan ServerEvent -> IO ()
dispatchMessage env req chan = do
    if reqMethod req == "notifications/initialized"
       then return ()
       else do
            resp <- routeRpc env req
            writeChan chan $ ServerEvent (Just $ stringUtf8 "message") Nothing [lazyByteString $ encode resp]

router :: Config -> KubernetesEnv -> Chan ServerEvent -> Application
router _ env msgChan request response =
    case (requestMethod request, pathInfo request) of
        ("GET", ["sse"]) -> do
            clientChan <- dupChan msgChan
            writeChan clientChan $ ServerEvent (Just $ stringUtf8 "endpoint") Nothing [stringUtf8 "/message"]
            eventSourceAppIO (readChan clientChan) request response

        ("POST", ["message"]) -> do
            body <- lazyRequestBody request
            case decode body :: Maybe JsonRpcRequest of
                Nothing -> response $ responseLBS status404 [] "Invalid JSON-RPC"
                Just req -> do
                    dispatchMessage env req msgChan
                    response $ responseLBS status202 [] "Accepted"

        ("GET", ["status"]) ->
            response $ responseLBS status200 [("Content-Type", "application/json")] (encode $ object ["name" .= ("kubernetes-mcp"::Text), "status" .= ("running"::Text)])
            
        _ -> response $ responseLBS status404 [("Content-Type", "text/plain")] "Not Found"

run :: Config -> KubernetesEnv -> IO ()
run cfg env = do
    let (Config.Port port) = Config.port cfg
    msgChan <- newChan
    let settings = setPort port $ setHost "0.0.0.0" $ setBeforeMainLoop (putStrLn $ "Socket bound. Ready for requests on port " ++ show port) defaultSettings
    runSettings settings (router cfg env msgChan)
