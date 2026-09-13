module Native.Encoding.Process
  ( Process
  , Exit
  , start
  , writeInput
  , closeInput
  , wait
  ) where

import Prelude

import Effect (Effect)
import Native.Graphics (Bytes)

type Exit = { success :: Boolean, code :: Int, stderr :: String }

foreign import data Process :: Type

-- | Starts a subprocess with piped stdin and captured stderr.
foreign import start :: String -> Array String -> Effect Process
foreign import writeInput :: Process -> Bytes -> Effect Unit
-- | Idempotent; waiting after a failed close remains safe.
foreign import closeInput :: Process -> Effect Unit
-- | Reaps the process, retaining its exit status for subsequent calls.
foreign import wait :: Process -> Effect Exit
