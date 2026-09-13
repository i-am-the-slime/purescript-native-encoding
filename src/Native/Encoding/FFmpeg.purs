module Native.Encoding.FFmpeg (executable) where

import Native.Graphics (Bytes)

-- | The platform-specific FFmpeg executable. Extraction and invocation are caller policy.
foreign import executable :: { bytes :: Bytes, name :: String }
