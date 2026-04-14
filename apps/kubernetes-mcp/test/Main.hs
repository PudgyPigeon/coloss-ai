{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Syd
import Data.Aeson (decode, encode, Value(..), object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List (isInfixOf)
import Data.Text (Text)
import qualified Data.Text as T
import Types
import Server (routeRpc)

-- | Mock Environment where everything succeeds
mockSuccessEnv :: KubernetesEnv
mockSuccessEnv = KubernetesEnv
    { envGetNamespaces = pure $ Right "default, kube-system"
    , envGetResources  = \rt ns -> pure $ Right ("Mock resources for " <> T.pack (show rt) <> " in " <> ns)
    , envGetLogs       = \_ name ns -> pure $ Right ("Mock logs for " <> name <> " in " <> ns)
    }

-- | Mock Environment where everything fails
mockFailEnv :: KubernetesEnv
mockFailEnv = KubernetesEnv
    { envGetNamespaces = pure $ Left "Timeout connecting to k8s"
    , envGetResources  = \_ _ -> pure $ Left "Timeout connecting to k8s"
    , envGetLogs       = \_ _ _ -> pure $ Left "Timeout connecting to k8s"
    }

main :: IO ()
main = sydTest $ do
    describe "Types Boundary - ResourceType ADT" $ do
        it "safely parses standard resources" $ do
            (Aeson.fromJSON (String "pods") :: Aeson.Result ResourceType) `shouldBe` Aeson.Success Pods
            (Aeson.fromJSON (String "deployments") :: Aeson.Result ResourceType) `shouldBe` Aeson.Success Deployments
            (Aeson.fromJSON (String "services") :: Aeson.Result ResourceType) `shouldBe` Aeson.Success Services
            
        it "gracefully fails on unknown strings instead of causing runtime stringly-typed crashes" $ do
            let res = Aeson.fromJSON (String "custom_resource_definitions") :: Aeson.Result ResourceType
            case res of
                Aeson.Error _ -> pure ()
                Aeson.Success _ -> expectationFailure "Should have failed to parse arbitrary string"

    describe "Server Boundary - JSON-RPC Routing Pipeline" $ do
        it "handles 'initialize' flawlessly" $ do
            let req = JsonRpcRequest "2.0" (Just $ Number 1) "initialize" Nothing
            resp <- routeRpc mockSuccessEnv req
            resJsonrpc resp `shouldBe` "2.0"
            resId resp `shouldBe` Number 1
            
        it "properly proxies a successful 'get_namespaces' tool call through the mock boundary" $ do
            let req = JsonRpcRequest "2.0" (Just $ Number 2) "tools/call" 
                        (Just $ object ["name" .= ("get_namespaces"::Text), "arguments" .= object []])
            resp <- routeRpc mockSuccessEnv req
            
            let encodedString = BL.unpack $ encode resp
            -- Verify isError is false and content matches mock
            encodedString `shouldSatisfy` (\s -> "\"isError\":false" `isInfixOf` s)
            encodedString `shouldSatisfy` (\s -> "default, kube-system" `isInfixOf` s)

        it "gracefully handles an injected cluster timeout error as a successful MCP content response with isError=True" $ do
            let req = JsonRpcRequest "2.0" (Just $ Number 3) "tools/call" 
                        (Just $ object ["name" .= ("get_namespaces"::Text), "arguments" .= object []])
            resp <- routeRpc mockFailEnv req
            
            let encodedString = BL.unpack $ encode resp
            -- Even though K8s failed, MCP handles failures using 'isError=True' inside the content block!
            encodedString `shouldSatisfy` (\s -> "\"isError\":true" `isInfixOf` s)
            encodedString `shouldSatisfy` (\s -> "Timeout connecting to k8s" `isInfixOf` s)
            
        it "generates a global handleError fallback for unknown tools or methods" $ do
            let req = JsonRpcRequest "2.0" (Just $ Number 4) "unknown/method" Nothing
            resp <- routeRpc mockSuccessEnv req
            
            let encodedString = BL.unpack $ encode resp
            encodedString `shouldSatisfy` (\s -> "\"error\"" `isInfixOf` s)
            encodedString `shouldSatisfy` (\s -> "-32601" `isInfixOf` s)

    describe "JSON-RPC Protocol Decoding (Types.hs)" $ do
        it "successfully decodes an MCP initialize JSON-RPC request" $ do
            let rawJson = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\", \"params\": {\"protocolVersion\": \"2024-11-05\"}}"
            let decoded = decode rawJson :: Maybe JsonRpcRequest
            
            case decoded of
                Nothing -> expectationFailure "Failed to decode valid JSON-RPC request"
                Just req -> do
                    reqJsonrpc req `shouldBe` "2.0"
                    reqId req `shouldBe` Just (Number 1)
                    reqMethod req `shouldBe` "initialize"
                    
        it "successfully decodes an MCP tools/list JSON-RPC request without params" $ do
            let rawJson = "{\"jsonrpc\": \"2.0\", \"id\": \"abc\", \"method\": \"tools/list\"}"
            let decoded = decode rawJson :: Maybe JsonRpcRequest
            
            case decoded of
                Nothing -> expectationFailure "Failed to decode valid JSON-RPC request missing params"
                Just req -> do
                    reqId req `shouldBe` Just (String "abc")
                    reqMethod req `shouldBe` "tools/list"
                    reqParams req `shouldBe` Nothing

    describe "JSON-RPC Protocol Encoding (Types.hs)" $ do
        it "successfully encodes an execution response correctly" $ do
            let resp = JsonRpcResponse
                    { resJsonrpc = "2.0"
                    , resId = Number 42
                    , resResult = Just (object ["content" .= [object ["text" .= ("hello" :: Text)]]])
                    , resError = Nothing
                    }
            let encodedString = BL.unpack $ encode resp
            
            encodedString `shouldSatisfy` (\s -> "\"jsonrpc\":\"2.0\"" `isInfixOf` s)
            encodedString `shouldSatisfy` (\s -> "\"id\":42" `isInfixOf` s)
            encodedString `shouldSatisfy` (\s -> "\"result\":{\"content\":[{\"text\":\"hello\"}]}" `isInfixOf` s)
            encodedString `shouldNotSatisfy` (\s -> "\"error\"" `isInfixOf` s)