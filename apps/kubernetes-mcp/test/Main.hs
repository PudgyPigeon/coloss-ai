module Main (main) where

-- import Test.Hspec
-- import MyLib (formatResourceName)

main :: IO ()
main = putStrLn "Test suite not yet implemented."

-- main :: IO()
-- main = hspec $ do
--     describe "Kubernetes Logic" $ do
--             it "converts a raw name to lowercase" $ do
--                 formatResourceName "Pod-Name" `shouldBe` "pod-name"

--             it "handles empty strings" $ do
--                 formatResourceName "" `shouldBe` ""