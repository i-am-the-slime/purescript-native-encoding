//go:build darwin && arm64

package native_encoding

import _ "embed"

//go:embed bin/ffmpeg_darwin_arm64
var ffmpegBinary []byte

func getFfmpeg() ([]byte, string) { return ffmpegBinary, "ffmpeg" }
