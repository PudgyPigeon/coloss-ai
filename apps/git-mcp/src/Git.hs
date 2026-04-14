{-# LANGUAGE OverloadedStrings #-}

module Git (
    getGitStatus,
    getGitLog,
    getGitCheckout,
    getGitCommit,
    getGitPush,
    getGitMR,
) where

import Control.Exception (SomeException, try)
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Process.Typed

runCommand :: String -> [String] -> IO (Either Text Text)
runCommand cmd args = do
    let p = setEnv [("GIT_TERMINAL_PROMPT", "0"), ("GH_PROMPT_DISABLED", "1")] $ setWorkingDir "." $ proc cmd args
    res <- try (readProcess p) :: IO (Either SomeException (ExitCode, BSL.ByteString, BSL.ByteString))
    case res of
        Right (ExitSuccess, stdout, _) ->
            return . Right . TE.decodeUtf8 . BSL.toStrict $ stdout
        Right (ExitFailure _, _, stderr) ->
            return . Left . TE.decodeUtf8 . BSL.toStrict $ stderr
        Left err ->
            return . Left . T.pack $ show err

getGitStatus :: IO (Either Text Text)
getGitStatus = runCommand "git" ["status", "-s"]

getGitLog :: Int -> IO (Either Text Text)
getGitLog count = runCommand "git" ["log", "-n", show count, "--oneline"]

getGitCheckout :: Text -> Bool -> IO (Either Text Text)
getGitCheckout branch isNew =
    if isNew
        then runCommand "git" ["checkout", "-b", T.unpack branch]
        else runCommand "git" ["checkout", T.unpack branch]

getGitCommit :: Text -> IO (Either Text Text)
getGitCommit msg = do
    _ <- runCommand "git" ["add", "."]
    runCommand "git" ["commit", "-m", T.unpack msg]

getGitPush :: Text -> IO (Either Text Text)
getGitPush remote = runCommand "git" ["push", T.unpack remote, "HEAD"]

getGitMR :: Text -> Text -> IO (Either Text Text)
getGitMR title body = runCommand "gh" ["pr", "create", "--title", T.unpack title, "--body", T.unpack body]
