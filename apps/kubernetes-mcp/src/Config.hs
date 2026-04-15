module Config (
    Config (..),
    Port (..),
    Env (..),
    Transport (..),
    get,
) where

import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import System.Environment (getArgs, lookupEnv)
import Text.Read (readMaybe)

-------------------------------------------------------------------------------
-- 1. Types & Validation
-------------------------------------------------------------------------------
newtype Port = Port Int deriving (Show, Eq)

-- | Pure validator for Port range
mkPort :: Int -> Maybe Port
mkPort n
    | n > 0 && n < 65_536 = Just (Port n)
    | otherwise = Nothing

-- | Sum type\Enum - The choices we allow in our logic
data Env = Dev | Staging | Prod deriving (Show, Eq)

mkEnv :: String -> Maybe Env
mkEnv "dev" = Just Dev
mkEnv "staging" = Just Staging
mkEnv "prod" = Just Prod
mkEnv _ = Nothing

-- | Transport mode for the MCP server
data Transport = Stdio | Http deriving (Show, Eq)

mkTransport :: String -> Maybe Transport
mkTransport "stdio" = Just Stdio
mkTransport "http" = Just Http
mkTransport _ = Nothing

data Config = Config
    { port :: Port
    , healthPort :: Port
    , env :: Env
    , transport :: Transport
    }
    deriving (Show, Eq)

-------------------------------------------------------------------------------
-- 2. Defaults
-------------------------------------------------------------------------------
defaultConfig :: Config
defaultConfig =
    Config
        { port = Port 30090
        , healthPort = Port 30091
        , env = Dev
        , transport = Stdio
        }

-------------------------------------------------------------------------------
-- 3. Configuration Loading (IO)
-------------------------------------------------------------------------------

-- | Primary entry point to fetch configuration
get :: IO Config
get = do
    args <- getArgs
    envPort <- lookupEnv "PORT"
    envHealthPort <- lookupEnv "HEALTH_PORT"
    envName <- lookupEnv "ENV"
    envTransport <- lookupEnv "TRANSPORT"

    -- Build base config from Environment or Defaults
    let base =
            defaultConfig
                { port = fromMaybe (port defaultConfig) (envPort >>= readMaybe >>= mkPort)
                , healthPort = fromMaybe (healthPort defaultConfig) (envHealthPort >>= readMaybe >>= mkPort)
                , env = fromMaybe (env defaultConfig) (envName >>= mkEnv . map toLower)
                , transport = fromMaybe (transport defaultConfig) (envTransport >>= mkTransport . map toLower)
                }

    -- Apply CLI overrides
    return $ parseArgs args base

-------------------------------------------------------------------------------
-- 4. Argument Parsing (The Smart Update Pattern)
-------------------------------------------------------------------------------

-- | Recursively walks the argument list and updates the Config record
parseArgs :: [String] -> Config -> Config
parseArgs ("--port" : v : rest) =
    parseArgs rest . \cfg -> cfg{port = fromMaybe (port cfg) (readMaybe v >>= mkPort)}
parseArgs ("--env" : v : rest) =
    parseArgs rest . \cfg -> cfg{env = fromMaybe (env cfg) (mkEnv (map toLower v))}
parseArgs ("--transport" : v : rest) =
    parseArgs rest . \cfg -> cfg{transport = fromMaybe (transport cfg) (mkTransport (map toLower v))}
parseArgs ("--health-port" : v : rest) =
    parseArgs rest . \cfg -> cfg{healthPort = fromMaybe (healthPort cfg) (readMaybe v >>= mkPort)}
parseArgs (_ : rest) = parseArgs rest
parseArgs [] = id
