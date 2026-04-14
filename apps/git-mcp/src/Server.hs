{-# LANGUAGE OverloadedStrings #-}

module Server (run, handleRpcRequest) where

import Config (Config (..), Port (..))
import Types (GitEnv (..), JsonRpcRequest (..), JsonRpcResponse (..))

import Control.Concurrent (MVar, newMVar, putMVar, takeMVar)
import Control.Monad (forever, void)
import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Builder qualified as Builder
import Data.Maybe (fromMaybe)

import Data.Text (Text)

import Network.HTTP.Types (hContentType, status200, status400, status404)
import Network.Wai (Application, Middleware, Response, ResponseReceived, pathInfo, responseLBS, responseStream, strictRequestBody)
import Network.Wai.Handler.Warp (runEnv)
import Network.Wai.Middleware.AddHeaders (addHeaders)

data AppState = AppState
    { eventChan :: MVar (Maybe Builder.Builder)
    }

run :: Config -> GitEnv -> IO ()
run cfg gitEnv = do
    let Port p = port cfg
    state <- AppState <$> newMVar Nothing
    putStrLn $ "Starting Git MCP server on port " ++ show p ++ "..."
    Network.Wai.Handler.Warp.runEnv p $
        corsMiddleware $
            router state gitEnv

corsMiddleware :: Middleware
corsMiddleware app req sendResponse = do
    let hdrs =
            [ ("Access-Control-Allow-Origin", "*")
            , ("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            , ("Access-Control-Allow-Headers", "Content-Type")
            ]
    addHeaders hdrs app req sendResponse

router :: AppState -> GitEnv -> Application
router state gitEnv req respond = case pathInfo req of
    [] -> respond $ responseLBS status200 [(hContentType, "text/plain")] "Git MCP Server"
    ["sse"] -> sseHandler state respond
    ["message"] -> messageHandler state gitEnv req respond
    _ -> respond $ responseLBS status404 [(hContentType, "text/plain")] "Not Found"

sseHandler :: AppState -> (Response -> IO ResponseReceived) -> IO ResponseReceived
sseHandler state respond = do
    putStrLn "New SSE client connected"
    let headers =
            [ (hContentType, "text/event-stream")
            , ("Cache-Control", "no-cache")
            , ("Connection", "keep-alive")
            ]
    respond $ responseStream status200 headers $ \write flush -> do
        write $ Builder.byteString "event: endpoint\n"
        write $ Builder.byteString "data: /message\n\n"
        flush
        forever $ do
            msg <- takeMVar (eventChan state)
            case msg of
                Just m -> do
                    write m
                    flush
                Nothing -> return ()

messageHandler :: AppState -> GitEnv -> Application
messageHandler state gitEnv req respond = do
    bodyLBS <- strictRequestBody req
    putStrLn $ "Received message: " ++ show bodyLBS
    case Aeson.decode bodyLBS of
        Just rpcReq -> do
            resp <- handleRpcRequest gitEnv rpcReq
            let respSse =
                    Builder.byteString "event: message\ndata: "
                        <> Builder.lazyByteString (Aeson.encode resp)
                        <> Builder.byteString "\n\n"
            void $ putMVar (eventChan state) (Just respSse)
            respond $ responseLBS status200 [(hContentType, "text/plain")] "Accepted"
        Nothing ->
            respond $ responseLBS status400 [(hContentType, "text/plain")] "Invalid JSON-RPC"

handleRpcRequest :: GitEnv -> JsonRpcRequest -> IO JsonRpcResponse
handleRpcRequest _gitEnv req@(JsonRpcRequest _ _ "initialize" _) =
    return $
        JsonRpcResponse
            "2.0"
            (Data.Maybe.fromMaybe Aeson.Null (reqId req))
            ( Just $
                object
                    [ "protocolVersion" .= ("2024-11-05" :: Text)
                    , "capabilities"
                        .= object
                            [ "tools" .= object []
                            ]
                    , "serverInfo"
                        .= object
                            [ "name" .= ("git-mcp" :: Text)
                            , "version" .= ("0.1.0" :: Text)
                            ]
                    ]
            )
            Nothing
handleRpcRequest _gitEnv req@(JsonRpcRequest _ _ "tools/list" _) =
    return $
        JsonRpcResponse
            "2.0"
            (Data.Maybe.fromMaybe Aeson.Null (reqId req))
            ( Just $
                object
                    [ "tools"
                        .= [ object ["name" .= ("git_status" :: Text), "description" .= ("Get local git status" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object []]]
                           , object ["name" .= ("git_log" :: Text), "description" .= ("Get recent git commits" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object ["count" .= object ["type" .= ("integer" :: Text)]]]]
                           , object ["name" .= ("git_checkout" :: Text), "description" .= ("Checkout branch" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object ["branch" .= object ["type" .= ("string" :: Text)], "isNew" .= object ["type" .= ("boolean" :: Text)]]]]
                           , object ["name" .= ("git_commit" :: Text), "description" .= ("Commit changes" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object ["message" .= object ["type" .= ("string" :: Text)]]]]
                           , object ["name" .= ("git_push" :: Text), "description" .= ("Push changes" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object ["remote" .= object ["type" .= ("string" :: Text)]]]]
                           , object ["name" .= ("git_mr" :: Text), "description" .= ("Create Merge Request" :: Text), "inputSchema" .= object ["type" .= ("object" :: Text), "properties" .= object ["title" .= object ["type" .= ("string" :: Text)], "body" .= object ["type" .= ("string" :: Text)]]]]
                           ]
                    ]
            )
            Nothing
handleRpcRequest gitEnv req@(JsonRpcRequest _ _ "tools/call" (Just (Aeson.Object params))) = do
    let toolName = case KeyMap.lookup "name" params of
            Just (Aeson.String n) -> n
            _ -> ""
        toolArgs = case KeyMap.lookup "arguments" params of
            Just (Aeson.Object a) -> a
            _ -> KeyMap.empty

    res <- case toolName of
        "git_status" -> envGitStatus gitEnv
        "git_log" -> do
            let count = case KeyMap.lookup "count" toolArgs of
                    Just (Aeson.Number c) -> round c
                    _ -> 10
            envGitLog gitEnv count
        "git_checkout" -> do
            let branch = case KeyMap.lookup "branch" toolArgs of
                    Just (Aeson.String b) -> b
                    _ -> "master"
                isNew = case KeyMap.lookup "isNew" toolArgs of
                    Just (Aeson.Bool b) -> b
                    _ -> False
            envGitCheckout gitEnv branch isNew
        "git_commit" -> do
            let msg = case KeyMap.lookup "message" toolArgs of
                    Just (Aeson.String m) -> m
                    _ -> "Update"
            envGitCommit gitEnv msg
        "git_push" -> do
            let remote = case KeyMap.lookup "remote" toolArgs of
                    Just (Aeson.String r) -> r
                    _ -> "origin"
            envGitPush gitEnv remote
        "git_mr" -> do
            let title = case KeyMap.lookup "title" toolArgs of
                    Just (Aeson.String t) -> t
                    _ -> "Merge Request"
                body = case KeyMap.lookup "body" toolArgs of
                    Just (Aeson.String b) -> b
                    _ -> "Please review my changes."
            envGitMR gitEnv title body
        _ -> return $ Left $ "Unknown tool: " <> toolName

    let contentResp = case res of
            Right msg -> [object ["type" .= ("text" :: Text), "text" .= msg]]
            Left err -> [object ["type" .= ("text" :: Text), "text" .= err]]
        isErrorResp = case res of
            Right _ -> False
            Left _ -> True

    return $
        JsonRpcResponse
            "2.0"
            (Data.Maybe.fromMaybe Aeson.Null (reqId req))
            ( Just $
                object
                    [ "content" .= contentResp
                    , "isError" .= isErrorResp
                    ]
            )
            Nothing
handleRpcRequest _ req =
    return $ JsonRpcResponse "2.0" (Data.Maybe.fromMaybe Aeson.Null (reqId req)) Nothing (Just $ object ["code" .= (-32601 :: Int), "message" .= ("Method not found" :: Text)])
