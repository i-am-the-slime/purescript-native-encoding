module Native.Encoding
  ( byteLength
  , sha256Hex
  , userCacheDirectory
  , joinPath
  , fileSize
  , makeDirectories
  , writeFile
  , chmod
  ) where

import Prelude

import Effect (Effect)
import Native.Graphics (Bytes)

foreign import byteLength :: Bytes -> Int
foreign import sha256Hex :: Bytes -> String
foreign import userCacheDirectory :: Effect String
foreign import joinPath :: Array String -> String
-- | Returns -1 when the path cannot be statted.
foreign import fileSize :: String -> Effect Int
foreign import makeDirectories :: Int -> String -> Effect Unit
foreign import writeFile :: Int -> String -> Bytes -> Effect Unit
foreign import chmod :: Int -> String -> Effect Unit
