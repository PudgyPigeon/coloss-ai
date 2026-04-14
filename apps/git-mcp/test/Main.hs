{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Text qualified as T
import Data.Vector qualified as Vector
import Server (handleRpcRequest)
import Test.Syd
import Types
import Data.Maybe (fromJust)

mockGitEnv :: GitEnv
mockGitEnv =
    GitEnv
        { envGitStatus = return $ Right " M src/Server.hs\n?? newfile.txt"
        , envGitLog = \_ -> return $ Right "a1b2c3d fix: testing mocked log"
        , envGitCheckout = \branch isNew ->
            if isNew && branch == "new-branch"
                then return $ Right "Switched to a new branch 'new-branch'"
                else return $ Left "Failed to checkout"
        , envGitCommit = \msg -> return $ Right $ "Committed: " <> msg
        , envGitPush = \_remote -> return $ Right "Everything up-to-date"
        , envGitMR = \title _body -> return $ Right $ "MR Created: " <> title
        }

main :: IO ()
main = sydTest $ do
    describe "Git-MCP Basic Tests" $ do
        it "loads fine" $ do
            True `shouldBe` True

    describe "MCP JSON-RPC Tools Boundaries" $ do
        it "resolves tools/list correctly" $ do
            let req = JsonRpcRequest "2.0" (Just (Number 1)) "tools/list" Nothing
            resp <- handleRpcRequest mockGitEnv req
            resError resp `shouldBe` Nothing
            let Object res = case resResult resp of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"
            KeyMap.member "tools" res `shouldBe` True

        it "resolves git_status successfully" $ do
            let req = JsonRpcRequest "2.0" (Just (Number 2)) "tools/call" (Just $ object ["name" .= ("git_status" :: T.Text), "arguments" .= object []])
            resp <- handleRpcRequest mockGitEnv req
            resError resp `shouldBe` Nothing
            let Object res = case resResult resp of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"
            KeyMap.lookup "isError" res `shouldBe` Just (Bool False)

            -- Extracting content text: {"content": [{"type": "text", "text": " M src/Server.hs\n?? newfile.txt"}]}
            let Array contentArray = case KeyMap.lookup "content" res of
                    Just (Array a) -> Array a
                    _ -> error "Expected Array"
            let Object firstElement = case contentArray Vector.!? 0 of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"
            KeyMap.lookup "text" firstElement `shouldBe` Just (String " M src/Server.hs\n?? newfile.txt")

        it "resolves git_checkout payload securely into GitEnv" $ do
            let req = JsonRpcRequest "2.0" (Just (Number 3)) "tools/call" (Just $ object ["name" .= ("git_checkout" :: T.Text), "arguments" .= object ["branch" .= ("new-branch" :: T.Text), "isNew" .= True]])
            resp <- handleRpcRequest mockGitEnv req
            resError resp `shouldBe` Nothing
            let Object res = case resResult resp of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"
            KeyMap.lookup "isError" res `shouldBe` Just (Bool False)

            let Array contentArray = case KeyMap.lookup "content" res of
                    Just (Array a) -> Array a
                    _ -> error "Expected Array"
            let Object firstElement = case contentArray Vector.!? 0 of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"
            KeyMap.lookup "text" firstElement `shouldBe` Just (String "Switched to a new branch 'new-branch'")

        it "catches failing execution cleanly as isError=True" $ do
            -- Our mockGitEnv fails when checking out anything other than 'new-branch' with isNew
            let req = JsonRpcRequest "2.0" (Just (Number 4)) "tools/call" (Just $ object ["name" .= ("git_checkout" :: T.Text), "arguments" .= object ["branch" .= ("master" :: T.Text), "isNew" .= True]])
            resp <- handleRpcRequest mockGitEnv req
            resError resp `shouldBe` Nothing
            let Object res = case resResult resp of
                    Just (Object o) -> Object o
                    _ -> error "Expected Object"

            -- Validation that it trapped to Left safely
            KeyMap.lookup "isError" res `shouldBe` Just (Bool True)
