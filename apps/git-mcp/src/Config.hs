module Config (Config (..), Port (..), get) where

import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import System.Environment (getArgs, lookupEnv)
import Text.Read (readMaybe)

newtype Port = Port Int deriving (Show, Eq)

mkPort :: Int -> Maybe Port
mkPort n
    | n > 0 && n < 65536 = Just (Port n)
    | otherwise = Nothing

data Env = Dev | Staging | Prod deriving (Show, Eq)
newtype EnvName = EnvName String deriving (Show, Eq)

mkEnv :: String -> Maybe Env
mkEnv "dev" = Just Dev
mkEnv "staging" = Just Staging
mkEnv "prod" = Just Prod
mkEnv _ = Nothing

data Config = Config
    { port :: Port
    , env :: Env
    }
    deriving (Show, Eq)

defaultConfig :: Config
defaultConfig = Config{port = Port 10000, env = Dev}

get :: IO Config
get = do
    args <- getArgs
    envPort <- lookupEnv "PORT"
    envName <- lookupEnv "ENV"
    let base =
            defaultConfig
                { port = fromMaybe (port defaultConfig) (envPort >>= readMaybe >>= mkPort)
                , env = fromMaybe (env defaultConfig) (envName >>= mkEnv . map toLower)
                }
    return $ parseArgs args base

parseArgs :: [String] -> Config -> Config
parseArgs ("--port" : v : rest) = parseArgs rest . \cfg -> cfg{port = fromMaybe (port cfg) (readMaybe v >>= mkPort)}
parseArgs ("--env" : v : rest) = parseArgs rest . \cfg -> cfg{env = fromMaybe (env cfg) (mkEnv (map toLower v))}
parseArgs (_ : rest) = parseArgs rest
parseArgs [] = id
