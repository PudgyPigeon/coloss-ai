{-# LANGUAGE RecordWildCards #-}
module Config 
    ( Config(..)
    , Port(..)
    , get
    ) where

import Data.Char (toLower)
import Control.Applicative ((<|>))
import System.Environment (getArgs, lookupEnv)
import Text.Read (readMaybe)
import Data.Maybe (fromMaybe)

-------------------------------------------------------------------------------
-- 1. Types & Validation
-------------------------------------------------------------------------------
newtype Port = Port Int deriving (Show, Eq)

-- | Pure validator for Port range
mkPort :: Int -> Maybe Port
mkPort n 
    | n > 0 && n < 65_536 = Just (Port n)
    | otherwise          = Nothing

-- | Sum type\Enum - The choices we allow in our logic
data Env = Dev | Staging | Prod deriving (Show, Eq)

-- | The type-safe wrapper for the actual string value
newtype EnvName = EnvName String deriving (Show, Eq)

mkEnv :: String -> Maybe Env
mkEnv "dev"     = Just Dev
mkEnv "staging" = Just Staging
mkEnv "prod"    = Just Prod
mkEnv _         = Nothing

data Config = Config
    { port      :: Port
    , env :: Env
    } deriving (Show, Eq)

-------------------------------------------------------------------------------
-- 2. Defaults
-------------------------------------------------------------------------------
defaultConfig :: Config
defaultConfig = Config 
    { port      = Port 10_000
    , env = Dev
    }

-------------------------------------------------------------------------------
-- 3. Configuration Loading (IO)
-------------------------------------------------------------------------------
-- | Primary entry point to fetch configuration
get :: IO Config 
get = do
    args         <- getArgs
    envPort      <- lookupEnv "PORT"
    envName      <- lookupEnv "ENV"
    
    -- Build base config from Environment or Defaults
    let base = defaultConfig 
          { port      = fromMaybe (port defaultConfig) (envPort >>= readMaybe >>= mkPort)
          , env = fromMaybe (env defaultConfig) (fmap (map toLower) envName >>= mkEnv)
          }

    -- Apply CLI overrides
    return $ parseArgs args base

-------------------------------------------------------------------------------
-- 4. Argument Parsing (The Smart Update Pattern)
-------------------------------------------------------------------------------
-- | Recursively walks the argument list and updates the Config record
parseArgs :: [String] -> Config -> Config
parseArgs ("--port" : v : rest) =
    parseArgs rest . \cfg -> cfg { port = fromMaybe (port cfg) (readMaybe v >>= mkPort) }

parseArgs ("--env" : v : rest) =
    parseArgs rest . \cfg -> cfg { env = fromMaybe (env cfg) (mkEnv (map toLower v)) }

parseArgs (_ : rest) = parseArgs rest
parseArgs [] = id