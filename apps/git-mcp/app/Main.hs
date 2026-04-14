module Main where

import Config (get)
import Git (getGitCheckout, getGitCommit, getGitLog, getGitMR, getGitPush, getGitStatus)
import Server (run)
import Types (GitEnv (..))

main :: IO ()
main = do
    cfg <- Config.get
    let activeEnv =
            GitEnv
                { envGitStatus = getGitStatus
                , envGitLog = getGitLog
                , envGitCheckout = getGitCheckout
                , envGitCommit = getGitCommit
                , envGitPush = getGitPush
                , envGitMR = getGitMR
                }
    run cfg activeEnv
