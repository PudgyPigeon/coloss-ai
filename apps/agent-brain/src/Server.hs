{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

module Server (run) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Proxy (Proxy(..))
import GHC.Generics (Generic)
import Servant
import Servant.API.Generic ((:-))
import Servant.Server.Generic (AsServerT) -- <--- THIS WAS MISSING
import Control.Monad.IO.Class (liftIO)
import qualified Network.Wai.Handler.Warp as Warp

-- 1. Data Model (Must be in scope)
data User = User
    { userId   :: Int
    , userName :: String
    } deriving (Eq, Show, Generic, ToJSON, FromJSON)

-- 2. API Record
data UserRoutes mode = UserRoutes
    { getUser  :: mode :- "user" :> Get '[JSON] User
    , postUser :: mode :- "user" :> ReqBody '[JSON] User :> Post '[JSON] User
    } deriving (Generic)

-- 3. The API Type
type UserAPI = NamedRoutes UserRoutes

-- 4. Wiring
userServer :: UserRoutes (AsServerT Handler)
userServer = UserRoutes
    { getUser  = getUserHandler
    , postUser = postUserHandler
    }

-- 5. Handlers
getUserHandler :: Handler User
getUserHandler = return $ User 1 "Tommy Nam"

postUserHandler :: User -> Handler User
postUserHandler newUser = do
    liftIO $ putStrLn $ "Received user: " ++ userName newUser
    return newUser

-- 6. Execution
run :: IO ()
run = do
    let port = 8080
    putStrLn $ "Starting Named Route Server on port " ++ show port
    Warp.run port (serve (Proxy :: Proxy UserAPI) userServer)