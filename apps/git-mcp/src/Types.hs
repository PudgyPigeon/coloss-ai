{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types where

import Data.Aeson (FromJSON (..), ToJSON (..), Value, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Text (Text)
import GHC.Generics (Generic)

data JsonRpcRequest = JsonRpcRequest
    { reqJsonrpc :: Text
    , reqId :: Maybe Value
    , reqMethod :: Text
    , reqParams :: Maybe Value
    }
    deriving (Show, Eq, Generic)

instance FromJSON JsonRpcRequest where
    parseJSON = Aeson.withObject "JsonRpcRequest" $ \o ->
        JsonRpcRequest
            <$> o .: "jsonrpc"
            <*> o .:? "id"
            <*> o .: "method"
            <*> o .:? "params"

data JsonRpcResponse = JsonRpcResponse
    { resJsonrpc :: Text
    , resId :: Value
    , resResult :: Maybe Value
    , resError :: Maybe Value
    }
    deriving (Show, Eq, Generic)

instance ToJSON JsonRpcResponse where
    toJSON r =
        Aeson.object $
            [ "jsonrpc" .= resJsonrpc r
            , "id" .= resId r
            ]
                ++ ( case resResult r of
                        Just res -> ["result" .= res]
                        Nothing -> []
                   )
                ++ ( case resError r of
                        Just err -> ["error" .= err]
                        Nothing -> []
                   )

-- | Dependency Injection Environment for Git Subprocesses
data GitEnv = GitEnv
    { envGitStatus :: IO (Either Text Text)
    , envGitLog :: Int -> IO (Either Text Text)
    , envGitCheckout :: Text -> Bool -> IO (Either Text Text)
    , envGitCommit :: Text -> IO (Either Text Text)
    , envGitPush :: Text -> IO (Either Text Text)
    , envGitMR :: Text -> Text -> IO (Either Text Text)
    }
