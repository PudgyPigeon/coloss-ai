{-# LANGUAGE OverloadedStrings #-}

module Config (
    Config (..),
    Port (..),
    Env (..),
    Transport (..),
    get,
) where

import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import Options.Applicative
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

-------------------------------------------------------------------------------
-- 1. Types & Pure Validation
-------------------------------------------------------------------------------
newtype Port = Port Int deriving (Show, Eq)

mkPort :: Int -> Maybe Port
mkPort n
    | n > 0 && n < 65536 = Just (Port n)
    | otherwise = Nothing

data Env = Dev | Staging | Prod deriving (Show, Eq)

mkEnv :: String -> Maybe Env
mkEnv s = case map toLower s of
    "dev"     -> Just Dev
    "staging" -> Just Staging
    "prod"    -> Just Prod
    _         -> Nothing

data Transport = Stdio | Http deriving (Show, Eq)

mkTransport :: String -> Maybe Transport
mkTransport s = case map toLower s of
    "stdio" -> Just Stdio
    "http"  -> Just Http
    _       -> Nothing

data Config = Config
    { port       :: Port
    , healthPort :: Port
    , env        :: Env
    , transport  :: Transport
    }
    deriving (Show, Eq)

-------------------------------------------------------------------------------
-- 2. Custom Option Readers
-------------------------------------------------------------------------------
readPort :: ReadM Port
readPort = maybeReader $ \s -> readMaybe s >>= mkPort

readEnv :: ReadM Env
readEnv = maybeReader mkEnv

readTransport :: ReadM Transport
readTransport = maybeReader mkTransport

-------------------------------------------------------------------------------
-- 3. Declarative Parser (Takes Defaults as an Argument)
-------------------------------------------------------------------------------

-- | The parser uses the injected 'defaults' as its fallback values.
configParser :: Config -> Parser Config
configParser defaults = Config
    <$> option readPort
        ( long "port"
       <> value (port defaults)
       <> showDefault
       <> help "Primary application port" )
    <*> option readPort
        ( long "health-port"
       <> value (healthPort defaults)
       <> showDefault
       <> help "Health check port" )
    <*> option readEnv
        ( long "env"
       <> value (env defaults)
       <> showDefault
       <> help "Environment (dev | staging | prod)" )
    <*> option readTransport
        ( long "transport"
       <> value (transport defaults)
       <> showDefault
       <> help "Transport mode (stdio | http)" )

-------------------------------------------------------------------------------
-- 4. Entry Point (IO)
-------------------------------------------------------------------------------

-- | Primary entry point to fetch configuration
get :: IO Config
get = do
    -- 1. Fetch from Environment
    envPortStr <- lookupEnv "PORT"
    envHealthStr <- lookupEnv "HEALTH_PORT"
    envNameStr <- lookupEnv "ENV"
    envTransportStr <- lookupEnv "TRANSPORT"

    -- 2. Safely parse Env Vars, falling back to absolute hardcoded defaults if missing
    let defaultPort      = fromMaybe (Port 30090) (envPortStr >>= readMaybe >>= mkPort)
        defaultHealth    = fromMaybe (Port 30091) (envHealthStr >>= readMaybe >>= mkPort)
        defaultEnv       = fromMaybe Dev          (envNameStr >>= mkEnv)
        defaultTransport = fromMaybe Stdio        (envTransportStr >>= mkTransport)

        -- This Config represents (Environment Variables OR Hardcoded Defaults)
        envDefaults = Config defaultPort defaultHealth defaultEnv defaultTransport

    -- 3. Run the parser, injecting envDefaults into the blueprint
    execParser $ info (configParser envDefaults <**> helper)
        ( fullDesc
       <> progDesc "Start the Kubernetes MCP server"
       <> header "Kubernetes MCP - Model Context Protocol Server" )